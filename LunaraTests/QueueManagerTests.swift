import Foundation
import Testing
@testable import Lunara

@MainActor
struct QueueManagerTests {
    @Test
    func playNow_startsFirstTrackAndPreloadsSecond() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 3)

        subject.manager.playNow(queueItems)
        await settleObservation()
        await waitUntil { subject.persistence.savedSnapshots.last?.currentIndex == 0 }

        #expect(subject.engine.playCalls.count == 1)
        #expect(subject.engine.playCalls.first?.1 == queueItems[0].trackID)
        #expect(subject.manager.currentItem?.trackID == queueItems[0].trackID)
        #expect(subject.engine.prepareNextCalls.contains(where: { $0.1 == queueItems[1].trackID }))

        let savedSnapshot = try #require(subject.persistence.savedSnapshots.last)
        #expect(savedSnapshot.currentIndex == 0)
        #expect(savedSnapshot.items == queueItems)
    }

    @Test
    func playNext_insertsImmediatelyAfterCurrentTrackAndPreloadsInsertedTrack() async throws {
        let subject = makeSubject()
        let nowItems = try makeQueueItems(count: 3, prefix: "now")
        let nextItems = try makeQueueItems(count: 2, prefix: "next")

        subject.manager.playNow(nowItems)
        subject.manager.playNext(nextItems)
        await settleObservation()

        #expect(subject.manager.items.map(\.trackID) == [
            nowItems[0].trackID,
            nextItems[0].trackID,
            nextItems[1].trackID,
            nowItems[1].trackID,
            nowItems[2].trackID
        ])
        #expect(subject.engine.prepareNextCalls.last?.1 == nextItems[0].trackID)
    }

    @Test
    func playLater_appendsToQueueAndKeepsImmediateNextPreload() async throws {
        let subject = makeSubject()
        let nowItems = try makeQueueItems(count: 2, prefix: "now")
        let laterItems = try makeQueueItems(count: 2, prefix: "later")

        subject.manager.playNow(nowItems)
        subject.manager.playLater(laterItems)
        await settleObservation()

        #expect(subject.manager.items.map(\.trackID) == [
            nowItems[0].trackID,
            nowItems[1].trackID,
            laterItems[0].trackID,
            laterItems[1].trackID
        ])
        #expect(subject.engine.prepareNextCalls.last?.1 == nowItems[1].trackID)
    }

    @Test
    func engineIdleAfterTrackEnds_autoAdvancesAndStartsNextTrack() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 3)
        subject.manager.playNow(queueItems)
        await settleObservation()

        subject.engine.currentTrackID = nil
        subject.engine.playbackState = .idle
        await settleObservation()

        #expect(subject.manager.currentItem?.trackID == queueItems[1].trackID)
        #expect(subject.engine.playCalls.count == 2)
        #expect(subject.engine.playCalls.last?.1 == queueItems[1].trackID)
    }

    @Test
    func engineTrackIDChange_updatesCurrentIndexAndPreloadsFollowingTrack() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 3)
        subject.manager.playNow(queueItems)
        await settleObservation()

        subject.engine.currentTrackID = queueItems[1].trackID
        subject.engine.playbackState = .playing
        subject.engine.elapsed = 12
        await settleObservation()
        await waitUntil { subject.persistence.savedSnapshots.contains(where: { $0.currentIndex == 1 }) }

        #expect(subject.manager.currentItem?.trackID == queueItems[1].trackID)
        #expect(subject.engine.prepareNextCalls.last?.1 == queueItems[2].trackID)
        #expect(subject.persistence.savedSnapshots.last?.currentIndex == 1)
    }

    @Test
    func restore_doesNotAutoPlayAndExplicitPlayUsesPersistedIndexAndElapsed() throws {
        let engine = PlaybackEngineMock()
        let queueItems = try makeQueueItems(count: 3)
        let persistence = QueueStatePersistenceMock()
        persistence.loadResult = QueueSnapshot(
            items: queueItems,
            currentIndex: 1,
            elapsed: 44
        )

        let manager = QueueManager(engine: engine, persistence: persistence)

        #expect(engine.playCalls.isEmpty)
        #expect(manager.currentItem?.trackID == queueItems[1].trackID)

        manager.play()

        #expect(engine.playCalls.count == 1)
        #expect(engine.playCalls.first?.1 == queueItems[1].trackID)
        #expect(engine.seekCalls == [44])
    }

    @Test
    func persistenceSaveFailure_setsLastErrorInsteadOfSilentlyIgnoring() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 2)
        subject.persistence.saveError = QueuePersistenceMockError.failed

        subject.manager.playNow(queueItems)
        await settleObservation()
        await waitUntil { subject.manager.lastError != nil }

        let error = try #require(subject.manager.lastError)
        switch error {
        case .queueOperationFailed(let reason):
            #expect(reason.contains("Failed to persist queue state"))
        default:
            Issue.record("Expected queueOperationFailed")
        }
    }

    @Test
    func clear_stopsPlaybackClearsQueueAndDeletesPersistedState() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 2)
        subject.manager.playNow(queueItems)

        subject.manager.clear()
        await settleObservation()
        await waitUntil { subject.persistence.clearCallCount == 1 }

        #expect(subject.manager.items.isEmpty)
        #expect(subject.manager.currentIndex == nil)
        #expect(subject.engine.stopCallCount == 1)
        #expect(subject.persistence.clearCallCount == 1)
    }

    @Test
    func duplicateTrackIDs_trackStartedEventResolvesToNearestForwardOccurrence() async throws {
        let subject = makeSubject()
        let duplicateURL = try #require(URL(string: "https://example.com/dup.mp3"))
        let items = [
            QueueItem(trackID: "dup", url: duplicateURL),
            QueueItem(trackID: "other", url: try #require(URL(string: "https://example.com/other.mp3"))),
            QueueItem(trackID: "dup", url: duplicateURL),
            QueueItem(trackID: "third", url: try #require(URL(string: "https://example.com/third.mp3")))
        ]

        subject.manager.playNow(items)
        await settleObservation()
        subject.manager.skipToNext()
        await settleObservation()

        subject.engine.currentTrackID = "dup"
        subject.engine.playbackState = .playing
        await settleObservation()

        #expect(subject.manager.currentIndex == 2)
    }

    @Test
    func elapsedProgress_persistsWhilePlayingWithoutQueueMutations() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 2)
        subject.manager.playNow(queueItems)
        await settleObservation()

        let initialSaveCount = subject.persistence.savedSnapshots.count
        subject.engine.elapsed = 6
        subject.engine.playbackState = .playing
        await settleObservation()
        await waitUntil { subject.persistence.savedSnapshots.last?.elapsed == 6 }

        #expect(subject.persistence.savedSnapshots.count > initialSaveCount)
        #expect(subject.persistence.savedSnapshots.last?.elapsed == 6)
    }

    @Test
    func restoreFailure_surfacesQueueOperationErrorAndStartsEmpty() {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        persistence.loadError = QueuePersistenceMockError.failed

        let manager = QueueManager(engine: engine, persistence: persistence)

        #expect(manager.items.isEmpty)
        #expect(manager.currentIndex == nil)
        let error: MusicError
        do {
            error = try #require(manager.lastError)
        } catch {
            Issue.record("Expected queue error to be present")
            return
        }
        switch error {
        case .queueOperationFailed(let reason):
            #expect(reason.contains("Failed to restore queue state"))
        default:
            Issue.record("Expected queueOperationFailed")
        }
    }

    @Test
    func reconcile_whenCurrentTrackRemoved_advancesToNextValidTrackAndPlaysIt() async throws {
        let subject = makeSubject()
        let queueItems = [
            QueueItem(trackID: "track-0", url: try #require(URL(string: "https://example.com/track-0.mp3"))),
            QueueItem(trackID: "track-1", url: try #require(URL(string: "https://example.com/track-1.mp3"))),
            QueueItem(trackID: "track-2", url: try #require(URL(string: "https://example.com/track-2.mp3")))
        ]

        subject.manager.playNow(queueItems)
        subject.manager.skipToNext()
        await settleObservation()

        subject.manager.reconcile(removingTrackIDs: ["track-1"])
        await settleObservation()

        #expect(subject.manager.items.map(\.trackID) == ["track-0", "track-2"])
        #expect(subject.manager.currentItem?.trackID == "track-2")
        #expect(subject.engine.playCalls.last?.1 == "track-2")
    }

    @Test
    func reconcile_whenCurrentTrackRetained_removesInvalidItemsWithoutRestartingPlayback() async throws {
        let subject = makeSubject()
        let queueItems = [
            QueueItem(trackID: "track-0", url: try #require(URL(string: "https://example.com/track-0.mp3"))),
            QueueItem(trackID: "track-1", url: try #require(URL(string: "https://example.com/track-1.mp3"))),
            QueueItem(trackID: "track-2", url: try #require(URL(string: "https://example.com/track-2.mp3")))
        ]

        subject.manager.playNow(queueItems)
        await settleObservation()
        let playCallCountBeforeReconcile = subject.engine.playCalls.count

        subject.manager.reconcile(removingTrackIDs: ["track-2"])
        await settleObservation()

        #expect(subject.manager.items.map(\.trackID) == ["track-0", "track-1"])
        #expect(subject.manager.currentItem?.trackID == "track-0")
        #expect(subject.engine.playCalls.count == playCallCountBeforeReconcile)
    }

    private func makeSubject() -> (
        manager: QueueManager,
        engine: PlaybackEngineMock,
        persistence: QueueStatePersistenceMock
    ) {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let manager = QueueManager(engine: engine, persistence: persistence)
        return (manager, engine, persistence)
    }

    private func makeQueueItems(count: Int, prefix: String = "track") throws -> [QueueItem] {
        try (0..<count).map { index in
            let url = try #require(URL(string: "https://example.com/\(prefix)-\(index).mp3"))
            return QueueItem(trackID: "\(prefix)-\(index)", url: url)
        }
    }

    private func settleObservation() async {
        await Task.yield()
        await Task.yield()
    }

    private func waitUntil(
        iterations: Int = 50,
        condition: @escaping () -> Bool
    ) async {
        for _ in 0..<iterations {
            if condition() {
                return
            }
            await Task.yield()
        }
    }
}
