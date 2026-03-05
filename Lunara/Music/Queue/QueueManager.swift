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
    var lastPersistedElapsed: TimeInterval = 0
    var pendingSeekAfterNextPlay: TimeInterval?
    private var persistenceTask: Task<Void, Never>?
    private var prepareNextTask: Task<Void, Never>?
    // Set during manual skip/navigation to prevent the observer from
    // re-syncing currentIndex to a stale engine trackID while the
    // new track is still loading via the track cache.
    private var manualNavigationTargetTrackID: String?

    init(
        engine: PlaybackEngineProtocol,
        persistence: QueueStatePersisting,
        trackCache: TrackCache? = nil,
        loudnessProvider: LoudnessDataProviding? = nil
    ) {
        self.engine = engine
        self.persistence = persistence
        self.trackCache = trackCache
        self.loudnessProvider = loudnessProvider
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

        playCurrentItem()
    }

    func playNext(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }

        if currentIndex == nil || self.items.isEmpty {
            self.items = items
            currentIndex = 0
            pendingSeekAfterNextPlay = nil
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
        items = []
        currentIndex = nil
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        engine.stop()
        enqueuePersistenceTask(
            operation: { [persistence] in
                try await persistence.clear()
            },
            failurePrefix: "Failed to clear queue state"
        )
    }

    func playCurrentItem() {
        guard let currentItem else { return }

        if trackCache != nil {
            engine.signalBuffering()
            Task {
                do {
                    let localURL = try await trackCache!.prepare(url: currentItem.url, trackID: currentItem.trackID)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        engine.play(url: localURL, trackID: currentItem.trackID)
                        if let pendingSeekAfterNextPlay {
                            engine.seek(to: pendingSeekAfterNextPlay)
                            self.pendingSeekAfterNextPlay = nil
                        }
                        persistQueueState(elapsed: engine.elapsed)
                        prepareNextTrackIfNeeded()
                    }
                } catch {
                    // Cache download failed — fall back to direct play
                    await MainActor.run {
                        engine.play(url: currentItem.url, trackID: currentItem.trackID)
                        if let pendingSeekAfterNextPlay {
                            engine.seek(to: pendingSeekAfterNextPlay)
                            self.pendingSeekAfterNextPlay = nil
                        }
                        persistQueueState(elapsed: engine.elapsed)
                        prepareNextTrackIfNeeded()
                    }
                }
            }
        } else {
            engine.play(url: currentItem.url, trackID: currentItem.trackID)

            if let pendingSeekAfterNextPlay {
                engine.seek(to: pendingSeekAfterNextPlay)
                self.pendingSeekAfterNextPlay = nil
            }

            persistQueueState(elapsed: engine.elapsed)
            prepareNextTrackIfNeeded()
        }
    }

    private func prepareNextTrackIfNeeded() {
        prepareNextTask?.cancel()
        guard engine.crossfadeEnabled,
              let currentIndex,
              let trackCache else { return }

        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }

        let currentItem = items[currentIndex]
        let nextItem = items[nextIndex]

        prepareNextTask = Task { [weak self, loudnessProvider] in
            do {
                let localURL = try await trackCache.prepare(url: nextItem.url, trackID: nextItem.trackID)

                guard !Task.isCancelled else { return }

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
                    self.engine.prepareNext(url: localURL, trackID: nextItem.trackID, transition: transition)
                }
            } catch {
                // Download failed - engine will fall back to normal track advancement
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
            _ = self.engine.elapsed
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
                // Engine still on stale track — don't sync or advance.
                if shouldPersistElapsedProgress() {
                    persistQueueState(elapsed: engine.elapsed)
                }
                return
            }
        }

        if engine.currentTrackID == nil, engine.playbackState == .idle {
            advanceAndPlayNextIfPossible()
        } else if let engineTrackID = engine.currentTrackID,
                  engineTrackID != currentItem?.trackID {
            // The engine advanced to a new track via crossfade —
            // sync currentIndex to match without re-triggering playback.
            syncCurrentIndexToEngineTrack(engineTrackID)
        }

        if shouldPersistElapsedProgress() {
            persistQueueState(elapsed: engine.elapsed)
        }
    }

    private func syncCurrentIndexToEngineTrack(_ engineTrackID: String) {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex),
              items[nextIndex].trackID == engineTrackID else { return }

        self.currentIndex = nextIndex
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        persistQueueState(elapsed: engine.elapsed)
        prepareNextTrackIfNeeded()
    }

    private func shouldPersistElapsedProgress() -> Bool {
        guard engine.currentTrackID != nil else { return false }
        guard engine.playbackState == .playing else { return false }

        let elapsed = max(0, engine.elapsed)
        if elapsed < lastPersistedElapsed {
            return true
        }

        return (elapsed - lastPersistedElapsed) >= 5
    }

    func applyReconciledItems(_ items: [QueueItem]) {
        self.items = items
    }

    func applyReconciledCurrentIndex(_ index: Int?) {
        currentIndex = index
    }
}
