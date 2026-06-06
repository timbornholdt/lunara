import Foundation
import Testing
@testable import Lunara

@MainActor
struct QueueManagerTests {
    @Test
    func playNow_startsFirstTrack() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 3)

        subject.manager.playNow(queueItems)
        await settleObservation()
        await waitUntil { subject.persistence.savedSnapshots.last?.currentIndex == 0 }

        #expect(subject.engine.playCalls.count == 1)
        #expect(subject.engine.playCalls.first?.1 == queueItems[0].trackID)
        #expect(subject.manager.currentItem?.trackID == queueItems[0].trackID)

        let savedSnapshot = try #require(subject.persistence.savedSnapshots.last)
        #expect(savedSnapshot.currentIndex == 0)
        #expect(savedSnapshot.items == queueItems)
    }

    @Test
    func playNext_insertsImmediatelyAfterCurrentTrack() async throws {
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
    }

    @Test
    func playLater_appendsToQueue() async throws {
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
    }

    @Test
    func engineIdleAfterTrackEnds_autoAdvancesAndStartsNextTrack() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 3)
        subject.manager.playNow(queueItems)
        // Wait for the first track to actually play before simulating it ending,
        // otherwise the forced-idle state races the in-flight resolve.
        await waitUntil { subject.engine.playCalls.count == 1 }

        subject.engine.currentTrackID = nil
        subject.engine.playbackState = .idle
        await waitUntil { subject.engine.playCalls.count == 2 }

        #expect(subject.manager.currentItem?.trackID == queueItems[1].trackID)
        #expect(subject.engine.playCalls.count == 2)
        #expect(subject.engine.playCalls.last?.1 == queueItems[1].trackID)
    }

    @Test
    func restore_doesNotAutoPlayAndExplicitPlayUsesPersistedIndexAndElapsed() async throws {
        let engine = PlaybackEngineMock()
        let queueItems = try makeQueueItems(count: 3)
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        persistence.loadResult = QueueSnapshot(
            items: queueItems,
            currentIndex: 1,
            elapsed: 44
        )

        let manager = QueueManager(engine: engine, persistence: persistence, resolver: resolver)

        #expect(engine.playCalls.isEmpty)
        #expect(manager.currentItem?.trackID == queueItems[1].trackID)

        manager.play()
        // Resolution happens off the main actor, so the play + resume-seek land
        // asynchronously. The persisted elapsed must survive the await window.
        await waitUntil { engine.playCalls.count == 1 }

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
    func elapsedProgress_persistsOnPause() async throws {
        let subject = makeSubject()
        let queueItems = try makeQueueItems(count: 2)
        subject.manager.playNow(queueItems)
        await settleObservation()

        let initialSaveCount = subject.persistence.savedSnapshots.count
        subject.engine.elapsed = 6
        subject.engine.playbackState = .playing
        await settleObservation()

        // Pausing should persist the current elapsed position
        subject.manager.pause()
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
            QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0"),
            QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1"),
            QueueItem(trackID: "track-2", streamKey: "/library/metadata/track-2")
        ]

        subject.manager.playNow(queueItems)
        subject.manager.skipToNext()
        await settleObservation()

        subject.manager.reconcile(removingTrackIDs: ["track-1"])
        await waitUntil { subject.engine.playCalls.last?.1 == "track-2" }

        #expect(subject.manager.items.map(\.trackID) == ["track-0", "track-2"])
        #expect(subject.manager.currentItem?.trackID == "track-2")
        #expect(subject.engine.playCalls.last?.1 == "track-2")
    }

    @Test
    func reconcile_whenCurrentTrackRetained_removesInvalidItemsWithoutRestartingPlayback() async throws {
        let subject = makeSubject()
        let queueItems = [
            QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0"),
            QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1"),
            QueueItem(trackID: "track-2", streamKey: "/library/metadata/track-2")
        ]

        subject.manager.playNow(queueItems)
        await waitUntil { subject.engine.playCalls.count == 1 }
        let playCallCountBeforeReconcile = subject.engine.playCalls.count

        subject.manager.reconcile(removingTrackIDs: ["track-2"])
        await settleObservation()

        #expect(subject.manager.items.map(\.trackID) == ["track-0", "track-1"])
        #expect(subject.manager.currentItem?.trackID == "track-0")
        #expect(subject.engine.playCalls.count == playCallCountBeforeReconcile)
    }

    @Test
    func reconcile_whenCurrentTrackRemovedAndNoNextValid_stopsPlaybackAndClearsCurrentSelection() async throws {
        let subject = makeSubject()
        let queueItems = [
            QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0"),
            QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1"),
            QueueItem(trackID: "track-2", streamKey: "/library/metadata/track-2")
        ]

        subject.manager.playNow(queueItems)
        subject.manager.skipToNext()
        subject.manager.skipToNext()
        await settleObservation()

        subject.manager.reconcile(removingTrackIDs: ["track-2"])
        await settleObservation()

        #expect(subject.manager.items.map(\.trackID) == ["track-0", "track-1"])
        #expect(subject.manager.currentIndex == nil)
        #expect(subject.manager.currentItem == nil)
        #expect(subject.engine.stopCallCount == 1)
    }

    // MARK: - skipBack Tests

    @Test
    func skipBack_whenElapsedMoreThan3s_seeksToZeroAndPersists() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 3)

        subject.manager.playNow(items)
        await settleObservation()

        subject.engine.elapsed = 5.0

        let seekCallsBefore = subject.engine.seekCalls.count
        subject.manager.skipBack()
        await settleObservation()

        #expect(subject.engine.seekCalls.count == seekCallsBefore + 1)
        #expect(subject.engine.seekCalls.last == 0.0)
        // currentIndex should remain unchanged
        #expect(subject.manager.currentIndex == 0)
    }

    @Test
    func skipBack_whenElapsed3sOrLess_withNoPreviousTrack_seeksToZero() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 3)

        subject.manager.playNow(items)
        await settleObservation()

        subject.engine.elapsed = 2.0

        let seekCallsBefore = subject.engine.seekCalls.count
        subject.manager.skipBack()
        await settleObservation()

        // At index 0 with elapsed ≤ 3s, no previous track → seeks to 0
        #expect(subject.engine.seekCalls.count == seekCallsBefore + 1)
        #expect(subject.engine.seekCalls.last == 0.0)
        #expect(subject.manager.currentIndex == 0)
    }

    @Test
    func skipBack_whenElapsed3sOrLess_withPreviousTrack_goesToPreviousTrack() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 3)

        subject.manager.playNow(items)
        subject.manager.skipToNext()
        await settleObservation()

        // Now at index 1, elapsed ≤ 3s
        subject.engine.elapsed = 1.0

        subject.manager.skipBack()
        await waitUntil { subject.engine.playCalls.last?.1 == items[0].trackID }

        #expect(subject.manager.currentIndex == 0)
        #expect(subject.manager.currentItem?.trackID == items[0].trackID)
        #expect(subject.engine.playCalls.last?.1 == items[0].trackID)
    }

    // MARK: - Lazy URL resolution (Lunara-uww.3.1 / 3.2)

    @Test
    func playNow_resolvesURLViaResolverAndPlaysResolvedURL() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 1)
        let resolved = try #require(URL(string: "https://cdn.example.com/resolved-0.mp3"))
        subject.resolver.resultsByTrackID[items[0].trackID] = [resolved]

        subject.manager.playNow(items)
        await waitUntil { subject.engine.playCalls.count == 1 }

        #expect(subject.resolver.resolvedTrackIDs.contains(items[0].trackID))
        #expect(subject.engine.playCalls.first?.0 == resolved)
        #expect(subject.engine.playCalls.first?.1 == items[0].trackID)
    }

    @Test
    func networkTrackPlay_signalsBufferingDuringResolve() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 1)

        subject.manager.playNow(items)
        await waitUntil { subject.engine.playCalls.count == 1 }

        #expect(subject.engine.signalBufferingCallCount >= 1)
    }

    @Test
    func downloadAfterEnqueue_secondResolveReturnsLocalFile_playsLocalFileOnReplay() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 1)
        let stream = try #require(URL(string: "https://cdn.example.com/stream-0.mp3"))
        let localFile = URL(fileURLWithPath: "/tmp/offline-0.m4a")
        // First resolve → remote stream; second resolve → local file (download
        // completed after enqueue). No queue rebuild required.
        subject.resolver.resultsByTrackID[items[0].trackID] = [stream, localFile]

        subject.manager.playNow(items)
        await waitUntil { subject.engine.playCalls.count == 1 }
        #expect(subject.engine.playCalls.first?.0 == stream)

        subject.manager.skipTo(index: 0)
        await waitUntil { subject.engine.playCalls.count == 2 }

        #expect(subject.engine.playCalls.last?.0 == localFile)
        #expect(subject.engine.playCalls.last?.0.isFileURL == true)
    }

    @Test
    func resolverThrows_setsLastError_doesNotPlay_retainsIndex_andDoesNotAutoAdvance() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 3)
        subject.resolver.error = QueuePersistenceMockError.failed

        subject.manager.playNow(items)
        await waitUntil { subject.manager.lastError != nil }
        // Let any (incorrect) auto-advance churn surface.
        await settleObservation()
        await settleObservation()

        #expect(subject.engine.playCalls.isEmpty)
        #expect(subject.manager.currentIndex == 0)
        #expect(subject.manager.currentItem?.trackID == items[0].trackID)
    }

    @Test
    func rapidSkip_supersedesInFlightResolve_onlyLatestTrackPlays() async throws {
        let subject = makeSubject()
        let items = try makeQueueItems(count: 3)
        // Hold track-1's resolve in flight so a later skip can supersede it.
        subject.resolver.gateResolution(forTrackID: items[1].trackID)

        subject.manager.playNow(items)
        await waitUntil { subject.engine.playCalls.last?.1 == items[0].trackID }

        subject.manager.skipTo(index: 1)
        await waitUntil { subject.resolver.resolvedTrackIDs.contains(items[1].trackID) }

        // Supersede the gated track-1 resolve with track-2 before track-1 finishes.
        subject.manager.skipTo(index: 2)
        await waitUntil { subject.engine.playCalls.last?.1 == items[2].trackID }

        // Now let the stale track-1 resolve complete — it must NOT reach the engine.
        subject.resolver.releaseGate()
        await settleObservation()
        await settleObservation()

        #expect(!subject.engine.playCalls.contains { $0.1 == items[1].trackID })
        #expect(subject.engine.playCalls.last?.1 == items[2].trackID)
        #expect(subject.manager.currentIndex == 2)
    }

    private func makeSubject() -> (
        manager: QueueManager,
        engine: PlaybackEngineMock,
        persistence: QueueStatePersistenceMock,
        resolver: PlaybackURLResolvingMock
    ) {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        let manager = QueueManager(engine: engine, persistence: persistence, resolver: resolver)
        return (manager, engine, persistence, resolver)
    }

    private func makeQueueItems(count: Int, prefix: String = "track") throws -> [QueueItem] {
        (0..<count).map { index in
            QueueItem(trackID: "\(prefix)-\(index)", streamKey: "/library/metadata/\(prefix)-\(index)")
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
