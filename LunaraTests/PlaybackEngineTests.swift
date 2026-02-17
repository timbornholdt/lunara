import AVFoundation
import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaybackEngineTests {
    @Test
    func play_configuresAudioSessionStartsDriverAndEntersBuffering() {
        let audioSession = AudioSessionMock()
        let driver = PlaybackEngineDriverMock()
        let timeoutScheduler = TimeoutSchedulerMock()
        let subject = AVQueuePlayerEngine(
            audioSession: audioSession,
            driver: driver,
            timeoutScheduler: timeoutScheduler,
            bufferingTimeout: 5
        )

        let url = URL(string: "https://example.com/track.mp3")!
        subject.play(url: url, trackID: "track-1")

        #expect(audioSession.configureForPlaybackCallCount == 1)
        #expect(driver.playCalls.count == 1)
        #expect(driver.playCalls.first?.0 == url)
        #expect(driver.playCalls.first?.1 == "track-1")
        #expect(subject.currentTrackID == "track-1")
        #expect(subject.playbackState == .buffering)
        #expect(timeoutScheduler.tasks.count == 1)
    }

    @Test
    func play_whenAudioSessionFails_transitionsToErrorAndSkipsDriverPlay() {
        let audioSession = AudioSessionMock()
        audioSession.configureForPlaybackError = MusicError.audioSessionFailed
        let driver = PlaybackEngineDriverMock()
        let timeoutScheduler = TimeoutSchedulerMock()
        let subject = AVQueuePlayerEngine(
            audioSession: audioSession,
            driver: driver,
            timeoutScheduler: timeoutScheduler
        )

        subject.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")

        #expect(driver.playCalls.isEmpty)
        #expect(driver.stopCallCount == 1)
        #expect(subject.playbackState == .error(MusicError.audioSessionFailed.userMessage))
    }

    @Test
    func playingStatusEvent_transitionsToPlayingAndCancelsTimeout() {
        let audioSession = AudioSessionMock()
        let driver = PlaybackEngineDriverMock()
        let timeoutScheduler = TimeoutSchedulerMock()
        let subject = AVQueuePlayerEngine(
            audioSession: audioSession,
            driver: driver,
            timeoutScheduler: timeoutScheduler
        )

        subject.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")
        let timeoutTask = try? #require(timeoutScheduler.tasks.last)

        driver.emitTimeControlStatus(.playing)

        #expect(subject.playbackState == .playing)
        #expect(timeoutTask?.cancelCallCount == 1)
    }

    @Test
    func bufferingTimeout_whenStillBuffering_transitionsToErrorAndStopsDriver() throws {
        let audioSession = AudioSessionMock()
        let driver = PlaybackEngineDriverMock()
        let timeoutScheduler = TimeoutSchedulerMock()
        let subject = AVQueuePlayerEngine(
            audioSession: audioSession,
            driver: driver,
            timeoutScheduler: timeoutScheduler
        )

        subject.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")

        let timeoutTask = try #require(timeoutScheduler.tasks.last)
        timeoutTask.fire()

        #expect(subject.playbackState == .error(MusicError.streamFailed(reason: "Playback timed out while buffering.").userMessage))
        #expect(driver.stopCallCount == 1)
    }

    @Test
    func streamFailureEvent_transitionsToErrorImmediately() {
        let subject = makeSubject()

        subject.engine.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")
        subject.driver.emitCurrentItemFailed("network dropped")

        #expect(subject.engine.playbackState == .error("network dropped"))
        #expect(subject.driver.stopCallCount == 1)
    }

    @Test
    func pause_andResume_forwardToDriverWithStateTransitions() {
        let subject = makeSubject()

        subject.engine.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")
        subject.driver.emitTimeControlStatus(.playing)
        subject.engine.pause()

        #expect(subject.engine.playbackState == .paused)
        #expect(subject.driver.pauseCallCount == 1)

        subject.engine.resume()

        #expect(subject.engine.playbackState == .buffering)
        #expect(subject.driver.resumeCallCount == 1)
    }

    @Test
    func resume_withoutLoadedTrack_transitionsToError() {
        let subject = makeSubject()

        subject.engine.resume()

        #expect(subject.engine.playbackState == .error(MusicError.invalidState(reason: "No track is loaded.").userMessage))
        #expect(subject.driver.resumeCallCount == 0)
    }

    @Test
    func prepareNext_forwardsCallWithoutChangingPlaybackState() {
        let subject = makeSubject()
        let url = URL(string: "https://example.com/track-next.mp3")!

        subject.engine.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")
        subject.driver.emitTimeControlStatus(.playing)
        subject.engine.prepareNext(url: url, trackID: "track-2")

        #expect(subject.driver.prepareNextCalls.count == 1)
        #expect(subject.driver.prepareNextCalls.first?.0 == url)
        #expect(subject.driver.prepareNextCalls.first?.1 == "track-2")
        #expect(subject.engine.playbackState == .playing)
    }

    @Test
    func seek_forwardsCallAndUpdatesElapsed() {
        let subject = makeSubject()

        subject.engine.seek(to: 42)

        #expect(subject.driver.seekCalls == [42])
        #expect(subject.engine.elapsed == 42)
    }

    @Test
    func stop_resetsPlaybackStateAndClearsTrack() {
        let subject = makeSubject()

        subject.engine.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")
        subject.driver.emitTimeControlStatus(.playing)
        subject.driver.emitElapsed(17)
        subject.driver.emitDuration(233)
        subject.engine.stop()

        #expect(subject.driver.stopCallCount == 1)
        #expect(subject.engine.playbackState == .idle)
        #expect(subject.engine.currentTrackID == nil)
        #expect(subject.engine.elapsed == 0)
        #expect(subject.engine.duration == 0)
    }

    @Test
    func interruptionCallbacks_pauseAndResumeWhenAllowed() {
        let subject = makeSubject()
        subject.engine.play(url: URL(string: "https://example.com/track.mp3")!, trackID: "track-1")
        subject.driver.emitTimeControlStatus(.playing)

        subject.audioSession.onInterruptionBegan?()

        #expect(subject.engine.playbackState == .paused)
        #expect(subject.driver.pauseCallCount == 1)

        subject.audioSession.onInterruptionEnded?(true)

        #expect(subject.engine.playbackState == .buffering)
        #expect(subject.driver.resumeCallCount == 1)

        subject.audioSession.onInterruptionEnded?(false)
        #expect(subject.driver.resumeCallCount == 1)
    }

    private func makeSubject() -> (
        engine: AVQueuePlayerEngine,
        audioSession: AudioSessionMock,
        driver: PlaybackEngineDriverMock,
        timeoutScheduler: TimeoutSchedulerMock
    ) {
        let audioSession = AudioSessionMock()
        let driver = PlaybackEngineDriverMock()
        let timeoutScheduler = TimeoutSchedulerMock()
        let engine = AVQueuePlayerEngine(
            audioSession: audioSession,
            driver: driver,
            timeoutScheduler: timeoutScheduler
        )
        return (engine, audioSession, driver, timeoutScheduler)
    }
}

private final class AudioSessionMock: AudioSessionProtocol {
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?

    private(set) var configureForPlaybackCallCount = 0
    var configureForPlaybackError: Error?

    func configureForPlayback() throws {
        configureForPlaybackCallCount += 1
        if let configureForPlaybackError {
            throw configureForPlaybackError
        }
    }
}
