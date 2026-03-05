import Foundation
import Observation
@testable import Lunara

@MainActor
@Observable
final class PlaybackEngineMock: PlaybackEngineProtocol {
    var playbackState: PlaybackState = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentTrackID: String?
    var crossfadeEnabled: Bool = false

    private(set) var playCalls: [(URL, String)] = []
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var stopCallCount = 0
    private(set) var prepareNextCalls: [(URL, String, TransitionStyle)] = []
    private(set) var signalBufferingCallCount = 0
    private(set) var skipWithFadeCallCount = 0

    func play(url: URL, trackID: String) {
        playCalls.append((url, trackID))
        currentTrackID = trackID
        playbackState = .playing
    }

    func pause() {
        pauseCallCount += 1
        playbackState = .paused
    }

    func resume() {
        resumeCallCount += 1
        playbackState = .playing
    }

    func seek(to time: TimeInterval) {
        seekCalls.append(time)
        elapsed = time
    }

    func stop() {
        stopCallCount += 1
        currentTrackID = nil
        elapsed = 0
        duration = 0
        playbackState = .idle
    }

    func prepareNext(url: URL, trackID: String, transition: TransitionStyle) {
        prepareNextCalls.append((url, trackID, transition))
    }

    func signalBuffering() {
        signalBufferingCallCount += 1
    }

    func skipWithFade() {
        skipWithFadeCallCount += 1
        currentTrackID = nil
        elapsed = 0
        duration = 0
        playbackState = .idle
    }
}

final class QueueStatePersistenceMock: QueueStatePersisting {
    var loadResult: QueueSnapshot?
    var loadError: Error?
    var saveError: Error?
    var clearError: Error?

    private(set) var savedSnapshots: [QueueSnapshot] = []
    private(set) var clearCallCount = 0

    func load() throws -> QueueSnapshot? {
        if let loadError {
            throw loadError
        }
        return loadResult
    }

    func save(_ snapshot: QueueSnapshot) async throws {
        if let saveError {
            throw saveError
        }
        savedSnapshots.append(snapshot)
    }

    func clear() async throws {
        if let clearError {
            throw clearError
        }
        clearCallCount += 1
    }
}

enum QueuePersistenceMockError: Error {
    case failed
}
