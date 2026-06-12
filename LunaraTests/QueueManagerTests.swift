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

    // MARK: - Reactive stream recovery on load failure (Lunara-uww.3.4)

    @Test
    func engineErrorOnOfflineFile_reResolvesForcingStream_andPlaysStreamURL() async throws {
        let subject = makeSubject()
        let item = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let offlineFile = URL(fileURLWithPath: "/tmp/offline-0.m4a")
        let streamURL = try #require(URL(string: "https://cdn.example.com/stream-0.mp3"))
        // First resolve (allowOffline) → corrupt offline file; second (forced stream) → stream.
        subject.resolver.resultsByTrackID["track-0"] = [offlineFile, streamURL]
        subject.engine.playFailsForURLs = [offlineFile]

        subject.manager.playNow([item])
        await waitUntil { subject.engine.playCalls.last?.0 == streamURL }

        #expect(subject.engine.playCalls.map(\.0) == [offlineFile, streamURL])
        // The retry must have forced a stream-only resolve.
        #expect(subject.resolver.resolveCalls.map(\.allowOffline) == [true, false])
        #expect(subject.manager.currentItem?.trackID == "track-0")
    }

    @Test
    func engineErrorOnStreamRetryToo_setsStreamFailed_andDoesNotLoop() async throws {
        let subject = makeSubject()
        let item = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let offlineFile = URL(fileURLWithPath: "/tmp/offline-0.m4a")
        let streamURL = try #require(URL(string: "https://cdn.example.com/stream-0.mp3"))
        subject.resolver.resultsByTrackID["track-0"] = [offlineFile, streamURL]
        // Both the offline file AND the stream fail to load.
        subject.engine.playFailsForURLs = [offlineFile, streamURL]

        subject.manager.playNow([item])
        await waitUntil { subject.manager.lastError != nil }
        // Allow any (incorrect) third recovery attempt to surface.
        await settleObservation()
        await settleObservation()

        // Exactly two plays (offline, stream) and two resolves — no infinite loop.
        #expect(subject.engine.playCalls.map(\.0) == [offlineFile, streamURL])
        #expect(subject.resolver.resolveCalls.count == 2)
        let error = try #require(subject.manager.lastError)
        guard case .streamFailed = error else {
            Issue.record("Expected .streamFailed, got \(error)")
            return
        }
    }

    @Test
    func recoveryGuardResets_perTrack_soNextTrackCanAlsoRecover() async throws {
        let subject = makeSubject()
        let item0 = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let item1 = QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1")
        let offline0 = URL(fileURLWithPath: "/tmp/offline-0.m4a")
        let offline1 = URL(fileURLWithPath: "/tmp/offline-1.m4a")
        let stream0 = try #require(URL(string: "https://cdn.example.com/stream-0.mp3"))
        let stream1 = try #require(URL(string: "https://cdn.example.com/stream-1.mp3"))
        subject.resolver.resultsByTrackID["track-0"] = [offline0, stream0]
        subject.resolver.resultsByTrackID["track-1"] = [offline1, stream1]
        // Both offline files fail; both streams succeed.
        subject.engine.playFailsForURLs = [offline0, offline1]

        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.playCalls.last?.0 == stream0 }

        subject.manager.skipToNext()
        await waitUntil { subject.engine.playCalls.last?.0 == stream1 }

        // track-1 recovered on its own, proving the per-track guard reset.
        #expect(subject.engine.playCalls.map(\.0) == [offline0, stream0, offline1, stream1])
        #expect(subject.manager.currentItem?.trackID == "track-1")
    }

    @Test
    func engineErrorOnStreamSource_doesNotRecover_setsStreamFailed() async throws {
        let subject = makeSubject()
        let item = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let streamURL = try #require(URL(string: "https://cdn.example.com/stream-0.mp3"))
        // The only source is a stream (no offline copy) and it fails to load.
        subject.resolver.resultsByTrackID["track-0"] = [streamURL]
        subject.engine.playFailsForURLs = [streamURL]

        subject.manager.playNow([item])
        await waitUntil { subject.manager.lastError != nil }
        await settleObservation()
        await settleObservation()

        // Re-streaming an already-streamed source can't help — no retry.
        #expect(subject.engine.playCalls.count == 1)
        #expect(subject.resolver.resolveCalls.count == 1)
        let error = try #require(subject.manager.lastError)
        guard case .streamFailed = error else {
            Issue.record("Expected .streamFailed, got \(error)")
            return
        }
    }

    @Test
    func engineError_whileResolveInFlight_doesNotTriggerRecovery() async throws {
        let subject = makeSubject()
        let item = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        // Hold the very first resolve in flight so isResolvingPlayback stays true.
        subject.resolver.gateResolution(forTrackID: "track-0")

        subject.manager.playNow([item])
        await waitUntil { subject.resolver.resolvedTrackIDs.contains("track-0") }

        // A late error lands while a resolve is still in flight — must be ignored.
        subject.engine.playbackState = .error("late error during resolve")
        await settleObservation()
        await settleObservation()

        // No recovery resolve happened (still just the single gated resolve).
        #expect(subject.resolver.resolveCalls.count == 1)
        subject.resolver.releaseGate()
    }

    @Test
    func crossfadeAdvancedTrackFailure_isNotRecovered_outOfScope() async throws {
        let subject = makeSubject()
        let item0 = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let item1 = QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1")
        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.playCalls.count == 1 }
        let resolveCountAfterFirstPlay = subject.resolver.resolveCalls.count

        // Engine crossfades into track-1 on its own (QueueManager never called play),
        // then that track errors. Per the bead this is out of scope — no recovery.
        subject.engine.currentTrackID = "track-1"
        await settleObservation()
        subject.engine.playbackState = .error("crossfade load failure")
        await settleObservation()
        await settleObservation()

        #expect(subject.resolver.resolveCalls.count == resolveCountAfterFirstPlay)
    }

    @Test
    func manualNavigationTargetFailure_stillRecovers() async throws {
        let subject = makeSubject()
        let item0 = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let item1 = QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1")
        let offline1 = URL(fileURLWithPath: "/tmp/offline-1.m4a")
        let stream1 = try #require(URL(string: "https://cdn.example.com/stream-1.mp3"))
        subject.resolver.resultsByTrackID["track-1"] = [offline1, stream1]
        subject.engine.playFailsForURLs = [offline1]

        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.playCalls.count == 1 }

        // skipTo sets manualNavigationTargetTrackID; the target's offline file then
        // fails to load. The engine never reaches the target trackID, so the .error
        // branch must fire ABOVE the manual-nav early-return.
        subject.manager.skipTo(index: 1)
        await waitUntil { subject.engine.playCalls.last?.0 == stream1 }

        // Recovery must have played the STREAM for the manual-nav target (not just
        // left the failed offline file as the last play).
        #expect(Array(subject.engine.playCalls.suffix(2).map(\.0)) == [offline1, stream1])
        #expect(subject.manager.currentItem?.trackID == "track-1")
    }

    @Test
    func recovery_preservesPlaybackPosition() async throws {
        let subject = makeSubject()
        let item = QueueItem(trackID: "track-0", streamKey: "/library/metadata/track-0")
        let offlineFile = URL(fileURLWithPath: "/tmp/offline-0.m4a")
        let streamURL = try #require(URL(string: "https://cdn.example.com/stream-0.mp3"))

        // Play the offline file successfully, accrue position, persist it.
        subject.resolver.resultsByTrackID["track-0"] = [offlineFile, streamURL]
        subject.manager.playNow([item])
        await waitUntil { subject.engine.playCalls.last?.0 == offlineFile }

        subject.engine.elapsed = 30
        subject.engine.playbackState = .paused          // persists elapsed → lastPersistedElapsed = 30
        await waitUntil { subject.persistence.savedSnapshots.last?.elapsed == 30 }

        // Now the offline file goes bad mid-track; recovery should resume near 30s.
        subject.engine.playFailsForURLs = []             // stream will succeed
        subject.engine.playbackState = .error("file became unreadable")
        await waitUntil { subject.engine.playCalls.last?.0 == streamURL }

        #expect(subject.engine.seekCalls.contains(30))
    }

    // MARK: - Cache failure is a play failure (Lunara-6jj)

    /// AVAudioPlayer cannot stream a remote URL, so when the track-cache download
    /// fails the engine must never be handed the remote URL as a "fallback" —
    /// the failure surfaces as an error and the item stays current for retry.
    @Test
    func cacheDownloadFailure_surfacesErrorInsteadOfPlayingRemoteURL() async throws {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        // Unroutable address: the cache download fails fast.
        resolver.resultsByTrackID["t0"] = [URL(string: "https://127.0.0.1:1/t0.mp3")!]
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-6jj-\(UUID().uuidString)", isDirectory: true)
        let manager = QueueManager(
            engine: engine,
            persistence: persistence,
            trackCache: TrackCache(cacheDirectory: cacheDir),
            resolver: resolver
        )

        manager.playNow([QueueItem(trackID: "t0", streamKey: "/k/t0")])
        // The failing download involves real (loopback) network I/O; yields alone
        // don't pass wall-clock time, so poll with short sleeps.
        for _ in 0..<300 where manager.lastError == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(manager.lastError != nil)
        // The engine never saw a URL it cannot play.
        #expect(engine.playCalls.allSatisfy { $0.0.isFileURL })
        #expect(manager.currentItem?.trackID == "t0") // retained for retry
    }

    // MARK: - Playback telemetry spans (Lunara-lz4)

    /// One `playStart` detail record per play, with the tap→audio breakdown.
    @Test
    func play_emitsPlayStartSpansWhenTelemetryEnabled() async throws {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        let telemetry = TelemetryEmittingMock()
        let manager = QueueManager(
            engine: engine,
            persistence: persistence,
            resolver: resolver,
            telemetry: telemetry
        )
        let items = try makeQueueItems(count: 2)

        manager.playNow(items)
        await waitUntil { telemetry.details.contains { $0.name == "playStart" } }

        let record = try #require(telemetry.details.first { $0.name == "playStart" })
        #expect(record.info["trackID"] == items[0].trackID)
        #expect(record.info["queueLength"] == "2")
        #expect(record.info["source"] != nil)
        #expect(record.info["resolveMs"] != nil)
        #expect(record.info["prepareMs"] != nil)
        #expect(record.info["totalMs"] != nil)
    }

    /// The crossfade decision is recorded with the chosen transition shape.
    @Test
    func prepareNext_emitsFadeDecisionWhenTelemetryEnabled() async throws {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        let telemetry = TelemetryEmittingMock()
        let manager = QueueManager(
            engine: engine,
            persistence: persistence,
            resolver: resolver,
            telemetry: telemetry
        )
        engine.crossfadeEnabled = true
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")

        manager.playNow([item0, item1])
        await waitUntil { telemetry.details.contains { $0.name == "fadeDecision" } }

        let record = try #require(telemetry.details.first { $0.name == "fadeDecision" })
        #expect(record.info["from"] == "t0")
        #expect(record.info["to"] == "t1")
        #expect(record.info["type"] == "crossfade")
        #expect(record.info["duration"] != nil)
        #expect(record.info["hadContour"] == "0")
    }

    /// Telemetry off ⇒ no detail records are even built.
    @Test
    func play_emitsNothingWhenTelemetryDisabled() async throws {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        let telemetry = TelemetryEmittingMock()
        telemetry.isEnabled = false
        let manager = QueueManager(
            engine: engine,
            persistence: persistence,
            resolver: resolver,
            telemetry: telemetry
        )

        manager.playNow(try makeQueueItems(count: 2))
        await waitUntil { engine.playCalls.count == 1 }
        await settleObservation()

        #expect(telemetry.details.isEmpty)
    }

    // MARK: - Crossfade loudness source (Lunara-9x1)

    /// The crossfade decision needs the OUTGOING track's contour (fade-out
    /// detection, Lunara-9x1) and the INCOMING track's contour (music-onset
    /// lead, Lunara-2vz) — outgoing first.
    @Test
    func prepareNext_fetchesLoudnessForOutgoingThenIncoming() async throws {
        let engine = PlaybackEngineMock()
        let persistence = QueueStatePersistenceMock()
        let resolver = PlaybackURLResolvingMock()
        let loudness = LoudnessProviderMock()
        let manager = QueueManager(
            engine: engine,
            persistence: persistence,
            loudnessProvider: loudness,
            resolver: resolver
        )
        engine.crossfadeEnabled = true
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")

        manager.playNow([item0, item1])
        await waitUntil { loudness.requestedTrackIDs.count >= 2 }

        #expect(loudness.requestedTrackIDs == ["t0", "t1"])
    }

    // MARK: - Loudness leveling gain handoff (Lunara-dtv)

    /// The current item's gain flows from the provider to the engine's play call.
    @Test
    func play_passesTrackGainToEngine() async throws {
        let engine = PlaybackEngineMock()
        let loudness = LoudnessProviderMock()
        loudness.gainByTrackID["t0"] = TrackGain(gain: -4.75, albumGain: -4.75)
        let manager = QueueManager(
            engine: engine,
            persistence: QueueStatePersistenceMock(),
            loudnessProvider: loudness,
            resolver: PlaybackURLResolvingMock()
        )

        manager.playNow([QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")])
        await waitUntil { engine.playGains.count == 1 }

        try #require(engine.playGains.count == 1)
        #expect(engine.playGains[0] == -4.75)
    }

    /// No gain row => the engine is told nil (plays unleveled at unity).
    @Test
    func play_withoutGain_passesNilToEngine() async throws {
        let engine = PlaybackEngineMock()
        let manager = QueueManager(
            engine: engine,
            persistence: QueueStatePersistenceMock(),
            loudnessProvider: LoudnessProviderMock(),
            resolver: PlaybackURLResolvingMock()
        )

        manager.playNow([QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")])
        await waitUntil { engine.playGains.count == 1 }

        try #require(engine.playGains.count == 1)
        #expect(engine.playGains[0] == nil)
    }

    /// A gain fetch stuck on the network must never hold up play start: the
    /// bounded wait expires and the track plays unleveled (Lunara-e0x).
    @Test
    func play_withWedgedGainFetch_stillStartsWithoutGain() async throws {
        let engine = PlaybackEngineMock()
        let loudness = LoudnessProviderMock()
        loudness.gainByTrackID["t0"] = TrackGain(gain: -6, albumGain: -6)
        loudness.gateGainForTrackID = "t0" // simulate slow metadata fetch
        let manager = QueueManager(
            engine: engine,
            persistence: QueueStatePersistenceMock(),
            loudnessProvider: loudness,
            resolver: PlaybackURLResolvingMock()
        )

        manager.playNow([QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")])
        // The bounded wait spends real wall time (up to ~150ms of 25ms ticks),
        // so poll with real sleeps — the yield-based waitUntil gives up too fast.
        for _ in 0..<60 where engine.playGains.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        try #require(engine.playGains.count == 1)
        #expect(engine.playGains[0] == nil) // played, unleveled
        loudness.releaseGainGate()
    }

    /// The incoming track's gain rides prepareNext, and the fadeDecision span
    /// records the exact number applied.
    @Test
    func prepareNext_passesNextGain_andRecordsItOnFadeDecision() async throws {
        let engine = PlaybackEngineMock()
        let loudness = LoudnessProviderMock()
        loudness.gainByTrackID["t1"] = TrackGain(gain: -12, albumGain: -12)
        let telemetry = TelemetryEmittingMock()
        let manager = QueueManager(
            engine: engine,
            persistence: QueueStatePersistenceMock(),
            loudnessProvider: loudness,
            resolver: PlaybackURLResolvingMock(),
            telemetry: telemetry
        )
        engine.crossfadeEnabled = true
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")

        manager.playNow([item0, item1])
        await waitUntil { engine.prepareNextGains.count == 1 }

        try #require(engine.prepareNextGains.count == 1)
        #expect(engine.prepareNextGains[0] == -12)
        await waitUntil { telemetry.details.contains { $0.name == "fadeDecision" } }
        let record = try #require(telemetry.details.first { $0.name == "fadeDecision" })
        #expect(record.info["gainDB"] == "-12.00")
    }

    // MARK: - Offline availability change → re-resolve preloaded next (Lunara-uww.3.6)

    @Test
    func offlineRemovedForNextAlbum_clearsPreparedNext_andReresolvesToStream() async throws {
        let subject = makeSubject()
        subject.engine.crossfadeEnabled = true
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")
        let offline1 = URL(fileURLWithPath: "/tmp/offline-t1.m4a")
        let stream1 = try #require(URL(string: "https://cdn.example.com/t1.mp3"))
        // First resolve → offline file (downloaded); second → stream (after removal).
        subject.resolver.resultsByTrackID["t1"] = [offline1, stream1]

        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.prepareNextCalls.last?.1 == "t1" }
        #expect(subject.engine.prepareNextCalls.last?.0 == offline1)

        // Album B's download is removed — the preloaded file:// is now dangling.
        subject.manager.offlineAvailabilityDidChange(forAlbums: ["album-B"])
        await waitUntil { subject.engine.prepareNextCalls.count >= 2 }

        #expect(subject.engine.clearPreparedNextCallCount == 1)
        #expect(subject.engine.prepareNextCalls.last?.1 == "t1")
        #expect(subject.engine.prepareNextCalls.last?.0 == stream1)
    }

    @Test
    func downloadCompletedForNextAlbum_reresolvesPreparedNextToOfflineFile() async throws {
        let subject = makeSubject()
        subject.engine.crossfadeEnabled = true
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")
        let stream1 = try #require(URL(string: "https://cdn.example.com/t1.mp3"))
        let offline1 = URL(fileURLWithPath: "/tmp/offline-t1.m4a")
        // First resolve → stream; second → offline file (download just completed).
        subject.resolver.resultsByTrackID["t1"] = [stream1, offline1]

        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.prepareNextCalls.last?.1 == "t1" }
        #expect(subject.engine.prepareNextCalls.last?.0 == stream1)

        subject.manager.offlineAvailabilityDidChange(forAlbums: ["album-B"])
        await waitUntil { subject.engine.prepareNextCalls.count >= 2 }

        #expect(subject.engine.prepareNextCalls.last?.0 == offline1)
        #expect(subject.engine.prepareNextCalls.last?.0.isFileURL == true)
    }

    @Test
    func offlineChangeForUnrelatedAlbum_doesNotReresolveNext() async throws {
        let subject = makeSubject()
        subject.engine.crossfadeEnabled = true
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")
        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.prepareNextCalls.last?.1 == "t1" }
        let prepareCountBefore = subject.engine.prepareNextCalls.count

        // A different album changed — the preloaded next is unaffected.
        subject.manager.offlineAvailabilityDidChange(forAlbums: ["album-Z"])
        await settleObservation()
        await settleObservation()

        #expect(subject.engine.clearPreparedNextCallCount == 0)
        #expect(subject.engine.prepareNextCalls.count == prepareCountBefore)
    }

    @Test
    func offlineChangeWhenCrossfadeDisabled_isNoOp() async throws {
        let subject = makeSubject()
        subject.engine.crossfadeEnabled = false
        let item0 = QueueItem(trackID: "t0", streamKey: "/k/t0", albumID: "album-A")
        let item1 = QueueItem(trackID: "t1", streamKey: "/k/t1", albumID: "album-B")
        subject.manager.playNow([item0, item1])
        await waitUntil { subject.engine.playCalls.count == 1 }
        // No preload happens without crossfade — nothing to invalidate.
        #expect(subject.engine.prepareNextCalls.isEmpty)
        let resolveCountBefore = subject.resolver.resolveCalls.count

        subject.manager.offlineAvailabilityDidChange(forAlbums: ["album-B"])
        await settleObservation()
        await settleObservation()

        #expect(subject.engine.clearPreparedNextCallCount == 0)
        #expect(subject.engine.prepareNextCalls.isEmpty)
        #expect(subject.resolver.resolveCalls.count == resolveCountBefore)
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
