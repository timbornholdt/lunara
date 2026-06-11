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
    // One-shot stream-recovery budget per track: set to the trackID when a load
    // failure triggers a forced-stream retry, so a second failure for the same
    // track stops instead of ping-ponging. Reset when a different track begins.
    private var streamRecoveryAttemptedTrackID: String?
    // Whether the URL most recently handed to engine.play was a file (offline file
    // or a cached stream). A load failure is only worth re-streaming when the
    // source was a file; an already-streamed source can't be improved by retrying.
    private var lastPlayedURLWasFile = false

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

    /// Plays the current queue item, resolving its URL at play time.
    /// - Parameter forceStream: when `true`, this is a reactive recovery retry —
    ///   the offline file is skipped and a fresh stream URL is forced, and the
    ///   per-track recovery budget is left intact (a normal play resets it).
    func playCurrentItem(forceStream: Bool = false) {
        guard let currentItem, let targetIndex = currentIndex, let resolver else { return }

        // A fresh, non-recovery play of an item restores its one-shot recovery budget.
        if !forceStream {
            streamRecoveryAttemptedTrackID = nil
        }

        // Supersede any in-flight resolve so a slower earlier one can't play late.
        currentPlayTask?.cancel()
        isResolvingPlayback = true
        // Move the engine off idle while we resolve, so the idle observer doesn't
        // treat the resolve window as queue exhaustion.
        engine.signalBuffering()

        let trackCache = self.trackCache
        let allowOffline = !forceStream
        currentPlayTask = Task { [weak self] in
            do {
                let resolvedURL = try await resolver.resolvePlaybackURL(for: currentItem, allowOffline: allowOffline)

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
                    self.lastPlayedURLWasFile = playURL.isFileURL
                    self.engine.play(url: playURL, trackID: currentItem.trackID)
                    self.isResolvingPlayback = false
                    // CrossfadeEngine reports a load failure synchronously via
                    // playbackState. On failure, skip persisting/preparing a dead
                    // play (a successful persist would also clear the error we're
                    // about to surface) and let the state observer drive recovery.
                    guard !self.engine.playbackState.hasError else { return }
                    self.consumePendingSeek()
                    self.persistQueueState(elapsed: self.engine.elapsed)
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
                let resolvedURL = try await resolver.resolvePlaybackURL(for: nextItem, allowOffline: true)

                var prepareURL = resolvedURL
                if !resolvedURL.isFileURL, let trackCache {
                    if let cached = try? await trackCache.prepare(url: resolvedURL, trackID: nextItem.trackID) {
                        prepareURL = cached
                    }
                }

                // The policy detects the fade-out at the END of the OUTGOING track,
                // so this must be the CURRENT item's contour, not the next's (Lunara-9x1).
                let loudness = try? await loudnessProvider?.fetchLoudnessLevels(trackID: currentItem.trackID)
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

    func offlineAvailabilityDidChange(forAlbums changedAlbumIDs: Set<String>) {
        // Only the crossfade preload snapshots a resolved URL ahead of play time;
        // without it the next track is resolved fresh at advance time, so there's
        // nothing stale to fix.
        guard engine.crossfadeEnabled else { return }
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }
        guard changedAlbumIDs.contains(items[nextIndex].albumID) else { return }

        // The preloaded next track's source is now stale (a removed offline file,
        // or a stream when a local copy just became available). Discard the staged
        // buffer synchronously — closing the window where the engine could fade into
        // it — then re-resolve and re-prepare from the correct source.
        engine.clearPreparedNext()
        prepareNextTrackIfNeeded()
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
        // A load failure must be handled before the manual-nav suppression below:
        // on a failed load the engine does NOT set currentTrackID, so the manual-nav
        // early-return would otherwise swallow the error and dead-end playback.
        if engine.playbackState.hasError {
            recoverFromPlaybackLoadFailure()
            return
        }

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

    /// Reactively recovers from an engine load failure on the current item —
    /// a corrupt/truncated offline file, a file deleted in the resolve→load race,
    /// or a stream that failed to load — by re-resolving with the offline file
    /// skipped and retrying playback once, resuming near the prior position.
    ///
    /// Keys off `currentItem` (not `engine.currentTrackID`, which the engine leaves
    /// untouched on a failed load). Crossfade/next-track load failures are out of
    /// scope: those are handled by the engine and the track re-resolves when it
    /// becomes current.
    private func recoverFromPlaybackLoadFailure() {
        // A failure that lands while a resolve is in flight belongs to a superseded
        // attempt — the in-flight play owns the outcome; don't double-recover.
        guard !isResolvingPlayback, let item = currentItem else { return }

        // Only a file source (offline file or a cached stream) is worth re-streaming.
        // A failure on an already-streamed source can't be improved by retrying it.
        guard lastPlayedURLWasFile else {
            lastError = .streamFailed(reason: "Playback failed and no alternate source is available.")
            return
        }

        // One forced-stream retry per track; a second failure stops, never loops.
        guard streamRecoveryAttemptedTrackID != item.trackID else {
            lastError = .streamFailed(reason: "Playback failed for both the offline file and the stream.")
            return
        }

        streamRecoveryAttemptedTrackID = item.trackID
        // We're taking over playback for this item; drop any manual-nav suppression.
        manualNavigationTargetTrackID = nil
        // Resume near where playback died.
        pendingSeekAfterNextPlay = lastPersistedElapsed
        playCurrentItem(forceStream: true)
    }

    private func syncCurrentIndexToEngineTrack(_ engineTrackID: String) {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }
        guard items[nextIndex].trackID == engineTrackID else { return }

        self.currentIndex = nextIndex
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        // The engine crossfaded into this track itself; we never called engine.play
        // for it, so the recovery state for the prior track no longer applies. Reset
        // it (and default lastPlayedURLWasFile to false) so an out-of-scope crossfade
        // failure doesn't trigger a spurious stream recovery off stale state.
        streamRecoveryAttemptedTrackID = nil
        lastPlayedURLWasFile = false
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
