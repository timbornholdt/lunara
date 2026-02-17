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

    private let engine: PlaybackEngineProtocol
    private let persistence: QueueStatePersisting
    private var observedTrackID: String?
    private var pendingSeekAfterNextPlay: TimeInterval?

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
        prepareUpcomingTrack()
        persistQueueState(elapsed: engine.elapsed)
    }

    func playLater(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }
        self.items.append(contentsOf: items)

        if currentIndex == nil {
            currentIndex = 0
        }

        prepareUpcomingTrack()
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

    func clear() {
        items = []
        currentIndex = nil
        pendingSeekAfterNextPlay = nil
        engine.stop()
        do {
            try persistence.clear()
            lastError = nil
        } catch {
            lastError = .queueOperationFailed(reason: "Failed to clear queue state: \(error.localizedDescription)")
        }
    }

    private func playCurrentItem() {
        guard let currentItem else { return }
        engine.play(url: currentItem.url, trackID: currentItem.trackID)

        if let pendingSeekAfterNextPlay {
            engine.seek(to: pendingSeekAfterNextPlay)
            self.pendingSeekAfterNextPlay = nil
        }

        prepareUpcomingTrack()
        persistQueueState(elapsed: engine.elapsed)
    }

    private func prepareUpcomingTrack() {
        guard let nextItem = nextItem() else { return }
        engine.prepareNext(url: nextItem.url, trackID: nextItem.trackID)
    }

    private func nextItem() -> QueueItem? {
        guard let currentIndex else { return nil }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return nil }
        return items[nextIndex]
    }

    private func advanceAndPlayNextIfPossible() {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }

        self.currentIndex = nextIndex
        pendingSeekAfterNextPlay = nil
        playCurrentItem()
    }

    private func restorePersistedQueue() {
        do {
            guard let snapshot = try persistence.load() else { return }
            items = snapshot.items

            if let snapshotIndex = snapshot.currentIndex, snapshot.items.indices.contains(snapshotIndex) {
                currentIndex = snapshotIndex
                pendingSeekAfterNextPlay = snapshot.elapsed
            } else if !snapshot.items.isEmpty {
                currentIndex = 0
                pendingSeekAfterNextPlay = snapshot.elapsed
            } else {
                currentIndex = nil
                pendingSeekAfterNextPlay = nil
            }

            lastError = nil
        } catch {
            items = []
            currentIndex = nil
            pendingSeekAfterNextPlay = nil
            lastError = .queueOperationFailed(reason: "Failed to restore queue state: \(error.localizedDescription)")
        }
    }

    private func persistQueueState(elapsed: TimeInterval) {
        let snapshot = QueueSnapshot(
            items: items,
            currentIndex: currentIndex,
            elapsed: max(0, elapsed)
        )

        do {
            try persistence.save(snapshot)
            lastError = nil
        } catch {
            lastError = .queueOperationFailed(reason: "Failed to persist queue state: \(error.localizedDescription)")
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
        let latestTrackID = engine.currentTrackID
        if observedTrackID != latestTrackID {
            observedTrackID = latestTrackID
            if let latestTrackID {
                handleTrackStarted(trackID: latestTrackID)
            }
        }

        if latestTrackID == nil, engine.playbackState == .idle {
            advanceAndPlayNextIfPossible()
        }
    }

    private func handleTrackStarted(trackID: String) {
        guard let startedIndex = items.firstIndex(where: { $0.trackID == trackID }) else { return }
        currentIndex = startedIndex
        prepareUpcomingTrack()
        persistQueueState(elapsed: engine.elapsed)
    }
}
