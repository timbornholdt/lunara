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

    private(set) var playCalls: [(URL, String)] = []
    private(set) var prepareNextCalls: [(URL, String)] = []
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var stopCallCount = 0

    func play(url: URL, trackID: String) {
        playCalls.append((url, trackID))
        currentTrackID = trackID
        playbackState = .playing
    }

    func prepareNext(url: URL, trackID: String) {
        prepareNextCalls.append((url, trackID))
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
