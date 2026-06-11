import Foundation
import Testing
@testable import Lunara

@MainActor
struct CrossfadeEngineTests {
    // MARK: - Test doubles

    /// A mock player slot whose `elapsed`/`trackID`/`volume` are directly
    /// controllable, so tests can simulate the outgoing track's EOF clock reset
    /// and the incoming track's fade progress without real audio.
    final class MockPlayerSlot: PlayerSlotProtocol {
        var trackID: String?
        var isActive = false
        var duration: TimeInterval = 200
        var elapsed: TimeInterval = 0
        var volume: Float = 1
        var isReadyForPlayback = true
        var onPlaybackComplete: (() -> Void)?

        private(set) var stopCallCount = 0
        private(set) var playCallCount = 0

        func load(url: URL, trackID: String) throws {
            self.trackID = trackID
        }

        func play() {
            isActive = true
            playCallCount += 1
        }

        func pause() {}
        func resume() {}

        func stop() {
            onPlaybackComplete = nil
            isActive = false
            trackID = nil
            stopCallCount += 1
        }

        func seek(to time: TimeInterval) {
            elapsed = time
        }
    }

    final class AudioSessionStub: AudioSessionProtocol {
        var onInterruptionBegan: (() -> Void)?
        var onInterruptionEnded: ((Bool) -> Void)?
        func configureForPlayback() throws {}
    }

    /// Builds an engine wired to two mock slots and starts a crossfade from
    /// track "A" into track "B" that is already in progress (isCrossfading).
    /// Returns the engine plus the outgoing (A) and incoming (B) mock slots.
    private func makeEngineMidCrossfade(
        fadeDuration: TimeInterval = 8
    ) -> (engine: CrossfadeEngine, outgoing: MockPlayerSlot, incoming: MockPlayerSlot) {
        let outgoing = MockPlayerSlot()
        let incoming = MockPlayerSlot()
        let slots: [MockPlayerSlot] = [outgoing, incoming]
        var handed = 0
        let engine = CrossfadeEngine(
            audioSession: AudioSessionStub(),
            slotFactory: {
                defer { handed += 1 }
                return slots[handed]
            }
        )

        let url = URL(string: "file:///track.mp3")!
        engine.play(url: url, trackID: "A")
        // Position the outgoing track near its end so the crossfade trigger
        // fires immediately (delay = startTime - elapsed <= 0).
        outgoing.elapsed = 190
        engine.prepareNext(
            url: url,
            trackID: "B",
            transition: .crossfade(startTime: 180, duration: fadeDuration)
        )
        return (engine, outgoing, incoming)
    }

    /// Builds an engine playing "A" with "B" prepared as the next crossfade
    /// target but NOT yet crossfading (outgoing positioned well before startTime).
    private func makeEngineWithPreparedNext(
        fadeDuration: TimeInterval = 8
    ) -> (engine: CrossfadeEngine, outgoing: MockPlayerSlot, incoming: MockPlayerSlot) {
        let outgoing = MockPlayerSlot()
        let incoming = MockPlayerSlot()
        let slots: [MockPlayerSlot] = [outgoing, incoming]
        var handed = 0
        let engine = CrossfadeEngine(
            audioSession: AudioSessionStub(),
            slotFactory: {
                defer { handed += 1 }
                return slots[handed]
            }
        )
        let url = URL(string: "file:///track.mp3")!
        engine.play(url: url, trackID: "A")
        outgoing.elapsed = 10 // well before startTime → trigger not yet armed to fire
        engine.prepareNext(
            url: url,
            trackID: "B",
            transition: .crossfade(startTime: 180, duration: fadeDuration)
        )
        return (engine, outgoing, incoming)
    }

    // MARK: - Phantom resume (Lunara-epq)

    /// An interruption that begins while the user has DELIBERATELY paused must
    /// not convert that pause into an interruption-pause — otherwise the
    /// interruption ending auto-resumes over the user's intent.
    @Test
    func interruptionCycleWhileUserPaused_doesNotAutoResume() {
        let outgoing = MockPlayerSlot()
        let incoming = MockPlayerSlot()
        let slots: [MockPlayerSlot] = [outgoing, incoming]
        var handed = 0
        let session = AudioSessionStub()
        let engine = CrossfadeEngine(
            audioSession: session,
            slotFactory: {
                defer { handed += 1 }
                return slots[handed]
            }
        )
        engine.play(url: URL(string: "file:///track.mp3")!, trackID: "A")
        engine.pause() // deliberate user pause

        // Siri / phone call / another app takes and releases audio focus.
        session.onInterruptionBegan?()
        session.onInterruptionEnded?(true)

        #expect(engine.playbackState == .paused)
        #expect(outgoing.playCallCount == 1) // never re-played
    }

    /// The legitimate case still works: an interruption that pauses ACTIVE
    /// playback resumes when the system says it should.
    @Test
    func interruptionDuringPlayback_stillAutoResumes() {
        let outgoing = MockPlayerSlot()
        let incoming = MockPlayerSlot()
        let slots: [MockPlayerSlot] = [outgoing, incoming]
        var handed = 0
        let session = AudioSessionStub()
        let engine = CrossfadeEngine(
            audioSession: session,
            slotFactory: {
                defer { handed += 1 }
                return slots[handed]
            }
        )
        engine.play(url: URL(string: "file:///track.mp3")!, trackID: "A")

        session.onInterruptionBegan?()
        #expect(engine.playbackState == .paused)
        session.onInterruptionEnded?(true)

        #expect(engine.playbackState == .playing)
    }

    // MARK: - Backgrounded elapsed timer (Lunara-n09)

    /// The 0.25s elapsed timer only feeds the in-app UI; while backgrounded it's
    /// pure battery waste (the lock screen interpolates position itself), so it
    /// stops on background and resumes on foreground.
    @Test
    func elapsedTimer_stopsWhileBackgroundedAndResumesOnForeground() {
        let (engine, outgoing, _) = makeEngineWithPreparedNext()
        _ = outgoing
        #expect(engine.isElapsedTimerRunningForTesting)

        engine.sceneDidChangeActivity(isActive: false)
        #expect(!engine.isElapsedTimerRunningForTesting)

        engine.sceneDidChangeActivity(isActive: true)
        #expect(engine.isElapsedTimerRunningForTesting)
    }

    /// Foregrounding while paused must NOT start the timer.
    @Test
    func foregroundingWhilePaused_doesNotStartElapsedTimer() {
        let (engine, _, _) = makeEngineWithPreparedNext()
        engine.pause()
        #expect(!engine.isElapsedTimerRunningForTesting)

        engine.sceneDidChangeActivity(isActive: false)
        engine.sceneDidChangeActivity(isActive: true)

        #expect(!engine.isElapsedTimerRunningForTesting)
    }

    /// Play that begins while backgrounded doesn't arm the UI timer until foreground.
    @Test
    func playWhileBackgrounded_armsTimerOnlyOnForeground() {
        let (engine, _, _) = makeEngineWithPreparedNext()
        engine.sceneDidChangeActivity(isActive: false)
        engine.pause()
        engine.resume()
        #expect(!engine.isElapsedTimerRunningForTesting)

        engine.sceneDidChangeActivity(isActive: true)
        #expect(engine.isElapsedTimerRunningForTesting)
    }

    // MARK: - Dead next-buffer health check (Lunara-uww.3.8)

    /// A staged next track whose source died (file evicted, resolve race) must not
    /// be faded into — that's a fade into silence. The engine discards it instead.
    @Test
    func beginCrossfade_withDeadNextBuffer_discardsInsteadOfFading() {
        let (engine, _, incoming) = makeEngineWithPreparedNext()
        incoming.isReadyForPlayback = false

        engine.beginCrossfade()

        #expect(engine.isCrossfading == false)
        #expect(incoming.playCallCount == 0)
        #expect(incoming.stopCallCount == 1) // staged buffer torn down
    }

    /// Same protection on the immediate-swap path: at EOF with a dead staged
    /// buffer, the engine goes idle (letting the queue re-resolve fresh) instead
    /// of playing the dead slot.
    @Test
    func trackEnded_withDeadNextBuffer_goesIdleInsteadOfSwapping() {
        let (engine, outgoing, incoming) = makeEngineWithPreparedNext()
        incoming.isReadyForPlayback = false

        outgoing.onPlaybackComplete?() // simulate EOF before any fade began

        #expect(engine.playbackState == .idle)
        #expect(incoming.playCallCount == 0)
        #expect(engine.currentTrackID == nil)
    }

    // MARK: - clearPreparedNext (Lunara-uww.3.6)

    @Test
    func clearPreparedNext_whenNotCrossfading_stopsInactiveSlot_andPreventsPromotionOnTrackEnd() {
        let (engine, outgoing, incoming) = makeEngineWithPreparedNext()
        #expect(engine.isCrossfading == false)
        #expect(incoming.trackID == "B")

        engine.clearPreparedNext()
        #expect(incoming.stopCallCount == 1)

        // Current track ends; with the prepared next cleared, B must NOT be promoted
        // (no fade into a now-stale buffer).
        outgoing.onPlaybackComplete?()
        #expect(incoming.playCallCount == 0)
    }

    @Test
    func clearPreparedNext_whileCrossfading_isNoOp() {
        let (engine, _, incoming) = makeEngineMidCrossfade()
        #expect(engine.isCrossfading == true)
        let stopsBefore = incoming.stopCallCount

        engine.clearPreparedNext()

        // The incoming slot is mid-fade and audible — it must not be torn down.
        #expect(incoming.stopCallCount == stopsBefore)
        #expect(engine.isCrossfading == true)
    }

    // MARK: - T1: root cause — completes via the incoming clock even when the
    // outgoing track's clock resets to 0 at end-of-file.

    @Test
    func updateCrossfade_completesWhenOutgoingClockResetsButIncomingReachedDuration() {
        let (engine, outgoing, incoming) = makeEngineMidCrossfade(fadeDuration: 8)
        #expect(engine.isCrossfading == true)

        // Outgoing file ended: AVAudioPlayer.currentTime resets toward 0.
        outgoing.elapsed = 0
        // Incoming track has played through the fade duration.
        incoming.elapsed = 8

        engine.updateCrossfade()

        #expect(engine.isCrossfading == false)
        #expect(engine.currentTrackID == "B")
        #expect(outgoing.trackID == nil) // outgoing slot released
        #expect(incoming.trackID == "B")
        #expect(incoming.volume == 1.0)
    }

    // MARK: - T2: safety net — outgoing track finishing mid-fade force-completes
    // the crossfade instead of being swallowed by the !isCrossfading guard.

    @Test
    func handleTrackEnded_whenOutgoingFinishesMidCrossfade_forceCompletes() {
        let (engine, outgoing, incoming) = makeEngineMidCrossfade()
        #expect(engine.isCrossfading == true)

        // Outgoing slot's onPlaybackComplete fires at its true EOF.
        outgoing.onPlaybackComplete?()

        #expect(engine.isCrossfading == false)
        #expect(engine.currentTrackID == "B")
        #expect(incoming.trackID == "B")
    }

    // MARK: - T3: completeCrossfade is idempotent — a second call (e.g. ramp
    // timer racing the EOF callback) must not stop/swap the new active track.

    @Test
    func completeCrossfade_calledTwice_secondCallIsNoOp() {
        let (engine, _, incoming) = makeEngineMidCrossfade(fadeDuration: 8)
        incoming.elapsed = 8
        engine.updateCrossfade() // first completion → active is now "B" (incoming)
        #expect(engine.currentTrackID == "B")

        let incomingStopsAfterFirst = incoming.stopCallCount
        engine.completeCrossfade() // second call must be a no-op

        #expect(incoming.stopCallCount == incomingStopsAfterFirst) // new active not stopped
        #expect(engine.currentTrackID == "B")
        #expect(engine.isCrossfading == false)
    }

    // MARK: - T4: pause/resume mid-fade must NOT jump-complete. The incoming
    // clock freezes while paused, so progress stays where it was.

    @Test
    func pauseResumeMidCrossfade_doesNotJumpComplete() {
        let (engine, _, incoming) = makeEngineMidCrossfade(fadeDuration: 8)
        incoming.elapsed = 3 // 3s into an 8s fade

        engine.pause()
        // (Incoming clock frozen — a wall clock would have advanced here.)
        engine.resume()
        engine.updateCrossfade()

        #expect(engine.isCrossfading == true) // still fading, not completed
        #expect(engine.currentTrackID == "A")

        engine.stop() // cancel the ramp timer
    }

    // MARK: - T5: scrubbing backward mid-fade must keep the next track loaded so
    // it still plays when the current track reaches the crossfade point again.

    @Test
    func seekMidCrossfade_keepsNextTrackReadyAndCanRetrigger() {
        let (engine, _, incoming) = makeEngineMidCrossfade(fadeDuration: 8)
        #expect(engine.isCrossfading == true)
        #expect(incoming.trackID == "B")

        // User scrubs backward during the fade.
        engine.seek(to: 10)

        // Fade is cancelled, but the preloaded next track must NOT be discarded.
        #expect(engine.isCrossfading == false)
        #expect(incoming.trackID == "B") // still loaded and ready
        #expect(incoming.elapsed == 0) // rewound for a clean re-trigger

        // Current track reaches the crossfade point again → fade re-triggers and
        // runs to completion, advancing to the next track.
        engine.beginCrossfade()
        incoming.elapsed = 8
        engine.updateCrossfade()

        #expect(engine.currentTrackID == "B")
        #expect(incoming.volume == 1.0)
    }

    // MARK: - Lunara-gf5: a USER pause must not be auto-resumed when an audio
    // interruption ends. Only an interruption-initiated pause may auto-resume,
    // and only when the system reports shouldResume == true.

    /// Builds an engine playing track "A", returning the engine and the audio
    /// session stub so tests can fire interruption began/ended callbacks.
    private func makeSingleTrackEngine() -> (engine: CrossfadeEngine, session: AudioSessionStub) {
        let session = AudioSessionStub()
        let engine = CrossfadeEngine(
            audioSession: session,
            slotFactory: { MockPlayerSlot() }
        )
        engine.play(url: URL(string: "file:///a.mp3")!, trackID: "A")
        return (engine, session)
    }

    @Test
    func manualPause_thenInterruptionEnded_doesNotAutoResume() {
        let (engine, session) = makeSingleTrackEngine()

        engine.pause() // user pause (e.g. lock-screen Pause)
        #expect(engine.playbackState == .paused)

        // A later interruption ends and reports it is resumable.
        session.onInterruptionEnded?(true)

        // The user paused — playback must stay paused.
        #expect(engine.playbackState == .paused)
    }

    @Test
    func interruptionPause_thenEndedShouldResumeTrue_resumes() {
        let (engine, session) = makeSingleTrackEngine()

        session.onInterruptionBegan?()
        #expect(engine.playbackState == .paused)

        session.onInterruptionEnded?(true)
        #expect(engine.playbackState == .playing)
    }

    @Test
    func interruptionPause_thenEndedShouldResumeFalse_staysPaused() {
        let (engine, session) = makeSingleTrackEngine()

        session.onInterruptionBegan?()
        session.onInterruptionEnded?(false)

        #expect(engine.playbackState == .paused)
    }

    @Test
    func userPauseDuringInterruption_isNotAutoResumedOnEnded() {
        let (engine, session) = makeSingleTrackEngine()

        session.onInterruptionBegan?()       // interruption pauses us
        engine.pause()                        // user then explicitly pauses too
        session.onInterruptionEnded?(true)    // interruption ends, resumable

        // The last intent was a user pause — stay paused.
        #expect(engine.playbackState == .paused)
    }
}
