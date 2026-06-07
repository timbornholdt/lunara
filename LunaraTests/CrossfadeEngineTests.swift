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
}
