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
    var lastPersistedElapsed: TimeInterval = 0
    var pendingSeekAfterNextPlay: TimeInterval?
    private var persistenceTask: Task<Void, Never>?

    init(
        engine: PlaybackEngineProtocol,
        persistence: QueueStatePersisting
    ) {
        self.engine = engine
        self.persistence = persistence
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
        advanceAndPlayNextIfPossible()
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
            playCurrentItem()
        }
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
        engine.play(url: currentItem.url, trackID: currentItem.trackID)

        if let pendingSeekAfterNextPlay {
            engine.seek(to: pendingSeekAfterNextPlay)
            self.pendingSeekAfterNextPlay = nil
        }

        persistQueueState(elapsed: engine.elapsed)
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
        if engine.currentTrackID == nil, engine.playbackState == .idle {
            advanceAndPlayNextIfPossible()
        }

        if shouldPersistElapsedProgress() {
            persistQueueState(elapsed: engine.elapsed)
        }
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
