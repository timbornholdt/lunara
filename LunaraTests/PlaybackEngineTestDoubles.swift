import AVFoundation
import Foundation
@testable import Lunara

final class PlaybackEngineDriverMock: PlaybackEngineDriver {
    var onTimeControlStatusChanged: ((AVPlayer.TimeControlStatus) -> Void)?
    var onCurrentTrackIDChanged: ((String?) -> Void)?
    var onCurrentItemFailed: ((String) -> Void)?
    var onCurrentItemEnded: (() -> Void)?
    var onElapsedChanged: ((TimeInterval) -> Void)?
    var onDurationChanged: ((TimeInterval) -> Void)?

    private(set) var playCalls: [(URL, String)] = []
    private(set) var prepareNextCalls: [(URL, String)] = []
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var stopCallCount = 0

    func play(url: URL, trackID: String) {
        playCalls.append((url, trackID))
    }

    func prepareNext(url: URL, trackID: String) {
        prepareNextCalls.append((url, trackID))
    }

    func pause() {
        pauseCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }

    func seek(to time: TimeInterval) {
        seekCalls.append(time)
    }

    func stop() {
        stopCallCount += 1
    }

    func emitTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        onTimeControlStatusChanged?(status)
    }

    func emitCurrentItemFailed(_ message: String) {
        onCurrentItemFailed?(message)
    }

    func emitElapsed(_ elapsed: TimeInterval) {
        onElapsedChanged?(elapsed)
    }

    func emitDuration(_ duration: TimeInterval) {
        onDurationChanged?(duration)
    }
}

final class TimeoutSchedulerMock: PlaybackTimeoutScheduling {
    private(set) var tasks: [TimeoutTaskMock] = []

    func schedule(after delay: TimeInterval, action: @escaping @Sendable () -> Void) -> PlaybackTimeoutTask {
        let task = TimeoutTaskMock(delay: delay, action: action)
        tasks.append(task)
        return task
    }
}

final class TimeoutTaskMock: PlaybackTimeoutTask {
    private let action: @Sendable () -> Void
    let delay: TimeInterval

    private(set) var cancelCallCount = 0
    private(set) var didFire = false

    init(delay: TimeInterval, action: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.action = action
    }

    func cancel() {
        cancelCallCount += 1
    }

    func fire() {
        guard !didFire else { return }
        didFire = true
        action()
    }
}

