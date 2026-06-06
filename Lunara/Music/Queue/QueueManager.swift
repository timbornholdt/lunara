import Foundation
import Observation

@MainActor
@Observable
final class QueueManager: QueueManagerProtocol {
    private(set) var items: [QueueItem] = []
    private(set) var currentIndex: Int?
    private(set) var lastError: MusicError?

    var currentItem: QueueItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else {
            return nil
        }
        return items[currentIndex]
    }

    let engine: PlaybackEngineProtocol
    private let persistence: QueueStatePersisting
    private let trackCache: TrackCache?
    private let loudnessProvider: LoudnessDataProviding?
    private let resolver: PlaybackURLResolving?
    var lastPersistedElapsed: TimeInterval = 0
    var pendingSeekAfterNextPlay: TimeInterval?
    private var persistenceTask: Task<Void, Never>?
    private var prepareNextTask: Task<Void, Never>?
    // The in-flight play resolution. Cancelled when a newer play supersedes it
    // (rapid skip), so a stale resolve can never reach the engine out of order.
    private var currentPlayTask: Task<Void, Never>?
    // True while a play's URL is being resolved off the main actor. Suppresses the
    // engine-idle auto-advance during the transient window before engine.play, so a
    // late idle notification can't be mistaken for queue exhaustion.
    private var isResolvingPlayback = false
    private var elapsedPersistenceTimer: Timer?
    // Set during manual skip/navigation to prevent the observer from
    // re-syncing currentIndex to a stale engine trackID while the
    // new track is still loading via the track cache.
    private var manualNavigationTargetTrackID: String?
    // Prevents the engine-idle observer from auto-advancing the queue
    // on a cold launch with a restored queue. Only set to true when
    // playback is explicitly triggered by the user.
    private var hasPlaybackBegun = false

    init(
        engine: PlaybackEngineProtocol,
        persistence: QueueStatePersisting,
        trackCache: TrackCache? = nil,
        loudnessProvider: LoudnessDataProviding? = nil,
        resolver: PlaybackURLResolving? = nil
    ) {
        self.engine = engine
        self.persistence = persistence
        self.trackCache = trackCache
        self.loudnessProvider = loudnessProvider
        self.resolver = resolver
        restorePersistedQueue()
        observeEngineState()
    }

    convenience init(engine: PlaybackEngineProtocol) {
        self.init(engine: engine, persistence: FileQueueStatePersistence())
    }

    func playNow(_ items: [QueueItem]) {
        guard !items.isEmpty else {
            clear()
            return
        }

        self.items = items
        currentIndex = 0
        pendingSeekAfterNextPlay = nil
        hasPlaybackBegun = true

        playCurrentItem()
    }

    func playNext(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }

        if currentIndex == nil || self.items.isEmpty {
            self.items = items
            currentIndex = 0
            pendingSeekAfterNextPlay = nil
            hasPlaybackBegun = true
            playCurrentItem()
            return
        }

        let insertionIndex = min((currentIndex ?? 0) + 1, self.items.count)
        self.items.insert(contentsOf: items, at: insertionIndex)
        persistQueueState(elapsed: engine.elapsed)
    }

    func playLater(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }
        self.items.append(contentsOf: items)

        if currentIndex == nil {
            currentIndex = 0
        }

        persistQueueState(elapsed: engine.elapsed)
    }

    func play() {
        hasPlaybackBegun = true
        if engine.currentTrackID == nil {
            playCurrentItem()
        } else {
            engine.resume()
        }
    }

    func pause() {
        engine.pause()
        persistQueueState(elapsed: engine.elapsed)
    }

    func resume() {
        hasPlaybackBegun = true
        if engine.currentTrackID == nil {
            playCurrentItem()
        } else {
            engine.resume()
        }
    }

    func skipToNext() {
        if engine.playbackState == .playing && engine.crossfadeEnabled {
            engine.skipWithFade()
            // The fade-out will transition to .idle, which triggers advanceAndPlayNextIfPossible
        } else {
            advanceAndPlayNextIfPossible()
        }
    }

    func skipBack() {
        guard let currentIndex else { return }
        if engine.elapsed > 3 {
            engine.seek(to: 0)
            persistQueueState(elapsed: 0)
        } else {
            let prevIndex = currentIndex - 1
            guard items.indices.contains(prevIndex) else {
                engine.seek(to: 0)
                persistQueueState(elapsed: 0)
                return
            }
            self.currentIndex = prevIndex
            pendingSeekAfterNextPlay = nil
            manualNavigationTargetTrackID = items[prevIndex].trackID
            playCurrentItem()
        }
    }

    func skipTo(index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        pendingSeekAfterNextPlay = nil
        manualNavigationTargetTrackID = items[index].trackID
        playCurrentItem()
    }

    func clear() {
        currentPlayTask?.cancel()
        prepareNextTask?.cancel()
        isResolvingPlayback = false
        items = []
        currentIndex = nil
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        hasPlaybackBegun = false
        stopElapsedPersistenceTimer()
        engine.stop()
        enqueuePersistenceTask(
            operation: { [persistence] in
                try await persistence.clear()
            },
            failurePrefix: "Failed to clear queue state"
        )
    }

    func playCurrentItem() {
        guard let currentItem, let targetIndex = currentIndex, let resolver else { return }

        // Supersede any in-flight resolve so a slower earlier one can't play late.
        currentPlayTask?.cancel()
        isResolvingPlayback = true
        // Move the engine off idle while we resolve, so the idle observer doesn't
        // treat the resolve window as queue exhaustion.
        engine.signalBuffering()

        let trackCache = self.trackCache
        currentPlayTask = Task { [weak self] in
            do {
                let resolvedURL = try await resolver.resolvePlaybackURL(for: currentItem)

                // Remote URLs route through the track cache (download/cache),
                // falling back to direct play if caching fails. Local files play directly.
                var playURL = resolvedURL
                if !resolvedURL.isFileURL, let trackCache {
                    if let cached = try? await trackCache.prepare(url: resolvedURL, trackID: currentItem.trackID) {
                        playURL = cached
                    }
                }

                try Task.checkCancellation()
                await MainActor.run {
                    guard let self else { return }
                    guard self.isCurrent(item: currentItem, index: targetIndex) else { return }
                    self.engine.play(url: playURL, trackID: currentItem.trackID)
                    self.consumePendingSeek()
                    self.persistQueueState(elapsed: self.engine.elapsed)
                    self.isResolvingPlayback = false
                    self.prepareNextTrackIfNeeded()
                }
            } catch is CancellationError {
                // Superseded by a newer play — a later task owns isResolvingPlayback.
                return
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    // Only fail the item that's still current; never play a stale URL.
                    guard self.isCurrent(item: currentItem, index: targetIndex) else { return }
                    self.lastError = .queueOperationFailed(
                        reason: "Failed to resolve playback URL: \(error.localizedDescription)"
                    )
                    // Retain currentIndex (no auto-advance); leave the engine where it
                    // is so a retry/play() re-attempts this same item.
                    self.isResolvingPlayback = false
                }
            }
        }
    }

    /// True only if the given item is still the current one (guards against a
    /// resolve that completed after the queue moved on).
    private func isCurrent(item: QueueItem, index: Int) -> Bool {
        !Task.isCancelled && currentIndex == index && currentItem?.trackID == item.trackID
    }

    private func consumePendingSeek() {
        if let pendingSeekAfterNextPlay {
            engine.seek(to: pendingSeekAfterNextPlay)
            self.pendingSeekAfterNextPlay = nil
        }
    }

    private func prepareNextTrackIfNeeded() {
        prepareNextTask?.cancel()
        guard engine.crossfadeEnabled,
              let currentIndex,
              let resolver else { return }

        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }

        let currentItem = items[currentIndex]
        let nextItem = items[nextIndex]
        let trackCache = self.trackCache

        prepareNextTask = Task { [weak self, loudnessProvider] in
            do {
                let resolvedURL = try await resolver.resolvePlaybackURL(for: nextItem)

                var prepareURL = resolvedURL
                if !resolvedURL.isFileURL, let trackCache {
                    if let cached = try? await trackCache.prepare(url: resolvedURL, trackID: nextItem.trackID) {
                        prepareURL = cached
                    }
                }

                let loudness = try? await loudnessProvider?.fetchLoudnessLevels(trackID: nextItem.trackID)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self else { return }
                    let transition = CrossfadePolicy.transition(
                        currentAlbumID: currentItem.albumID,
                        currentTrackNumber: currentItem.trackNumber,
                        nextAlbumID: nextItem.albumID,
                        nextTrackNumber: nextItem.trackNumber,
                        currentTrackDuration: self.engine.duration,
                        loudnessLevels: loudness
                    )
                    self.engine.prepareNext(url: prepareURL, trackID: nextItem.trackID, transition: transition)
                }
            } catch {
                // Resolve or cache prep failed — skip preparing the next track.
            }
        }
    }

    private func advanceAndPlayNextIfPossible() {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else {
            handleQueueExhausted()
            return
        }

        self.currentIndex = nextIndex
        pendingSeekAfterNextPlay = nil
        playCurrentItem()
    }

    private func handleQueueExhausted() {
        self.currentIndex = nil
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        engine.stop()
        persistQueueState(elapsed: 0)
    }

    private func restorePersistedQueue() {
        do {
            guard let snapshot = try persistence.load() else { return }
            items = snapshot.items

            if let snapshotIndex = snapshot.currentIndex, snapshot.items.indices.contains(snapshotIndex) {
                currentIndex = snapshotIndex
                pendingSeekAfterNextPlay = snapshot.elapsed
                lastPersistedElapsed = snapshot.elapsed
            } else if !snapshot.items.isEmpty {
                currentIndex = 0
                pendingSeekAfterNextPlay = snapshot.elapsed
                lastPersistedElapsed = snapshot.elapsed
            } else {
                currentIndex = nil
                pendingSeekAfterNextPlay = nil
                lastPersistedElapsed = 0
            }

            lastError = nil
        } catch {
            items = []
            currentIndex = nil
            pendingSeekAfterNextPlay = nil
            lastPersistedElapsed = 0
            lastError = .queueOperationFailed(reason: "Failed to restore queue state: \(error.localizedDescription)")
        }
    }

    func persistQueueState(elapsed: TimeInterval) {
        let clampedElapsed = max(0, elapsed)
        lastPersistedElapsed = clampedElapsed
        let snapshot = QueueSnapshot(
            items: items,
            currentIndex: currentIndex,
            elapsed: clampedElapsed
        )

        enqueuePersistenceTask(
            operation: { [persistence] in
                try await persistence.save(snapshot)
            },
            failurePrefix: "Failed to persist queue state"
        )
    }

    private func enqueuePersistenceTask(
        operation: @escaping @Sendable () async throws -> Void,
        failurePrefix: String
    ) {
        let previousTask = persistenceTask
        persistenceTask = Task { [weak self] in
            await previousTask?.value
            do {
                try await operation()
                await MainActor.run {
                    self?.lastError = nil
                }
            } catch {
                await MainActor.run {
                    self?.lastError = .queueOperationFailed(reason: "\(failurePrefix): \(error.localizedDescription)")
                }
            }
        }
    }

    private func observeEngineState() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.engine.currentTrackID
            _ = self.engine.playbackState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleEngineStateChange()
                self?.observeEngineState()
            }
        }
    }

    private func handleEngineStateChange() {
        // If a manual navigation is in progress (skipBack/skipTo), suppress
        // auto-sync until the engine starts playing the intended track.
        if let targetID = manualNavigationTargetTrackID {
            if engine.currentTrackID == targetID {
                manualNavigationTargetTrackID = nil
            } else {
                return
            }
        }

        if engine.currentTrackID == nil, engine.playbackState == .idle, hasPlaybackBegun, !isResolvingPlayback {
            advanceAndPlayNextIfPossible()
        } else if let engineTrackID = engine.currentTrackID,
                  engineTrackID != currentItem?.trackID {
            syncCurrentIndexToEngineTrack(engineTrackID)
        }

        // Start or stop the periodic persistence timer based on playback state
        if engine.playbackState == .playing {
            startElapsedPersistenceTimer()
        } else {
            stopElapsedPersistenceTimer()
            // Persist immediately on pause/stop so we capture the final position
            if engine.currentTrackID != nil {
                persistQueueState(elapsed: engine.elapsed)
            }
        }
    }

    private func startElapsedPersistenceTimer() {
        guard elapsedPersistenceTimer == nil else { return }
        elapsedPersistenceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine.playbackState == .playing else { return }
                self.persistQueueState(elapsed: self.engine.elapsed)
            }
        }
    }

    private func stopElapsedPersistenceTimer() {
        elapsedPersistenceTimer?.invalidate()
        elapsedPersistenceTimer = nil
    }

    private func syncCurrentIndexToEngineTrack(_ engineTrackID: String) {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }
        guard items[nextIndex].trackID == engineTrackID else { return }

        self.currentIndex = nextIndex
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        persistQueueState(elapsed: engine.elapsed)
        prepareNextTrackIfNeeded()
    }

    func applyReconciledItems(_ items: [QueueItem]) {
        self.items = items
    }

    func applyReconciledCurrentIndex(_ index: Int?) {
        currentIndex = index
    }
}
