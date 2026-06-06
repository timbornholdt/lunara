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

/// Resolves playback URLs at play time for QueueManager tests.
///
/// Defaults to echoing a deterministic remote (non-file) URL per stream key so
/// the network branch is exercised. Per-trackID overrides, sequenced results
/// (e.g. stream first, local file second to model a download completing after
/// enqueue), and a thrown error are all configurable.
final class PlaybackURLResolvingMock: PlaybackURLResolving, @unchecked Sendable {
    /// Sequenced results keyed by trackID; each call pops the next, then the last
    /// repeats. Use to model a download completing between plays.
    var resultsByTrackID: [String: [URL]] = [:]
    var errorByTrackID: [String: Error] = [:]
    var error: Error?

    private(set) var resolvedTrackIDs: [String] = []
    private let lock = NSLock()

    /// When set, resolution for this trackID suspends until `releaseGate()` is
    /// called — used to hold a resolve "in flight" while a later skip supersedes it.
    private var gateTrackID: String?
    private var gateContinuation: CheckedContinuation<Void, Never>?

    func gateResolution(forTrackID trackID: String) {
        lock.lock()
        gateTrackID = trackID
        lock.unlock()
    }

    func releaseGate() {
        lock.lock()
        let continuation = gateContinuation
        gateContinuation = nil
        gateTrackID = nil
        lock.unlock()
        continuation?.resume()
    }

    func resolvePlaybackURL(for item: QueueItem) async throws -> URL {
        lock.lock()
        resolvedTrackIDs.append(item.trackID)
        let isGated = item.trackID == gateTrackID
        lock.unlock()

        if isGated {
            await withCheckedContinuation { continuation in
                lock.lock()
                gateContinuation = continuation
                lock.unlock()
            }
        }

        if let error {
            throw error
        }
        if let trackError = errorByTrackID[item.trackID] {
            throw trackError
        }

        lock.lock()
        defer { lock.unlock() }
        if var queued = resultsByTrackID[item.trackID], !queued.isEmpty {
            let next = queued.count > 1 ? queued.removeFirst() : queued[0]
            resultsByTrackID[item.trackID] = queued
            return next
        }
        return URL(string: "https://resolver.example.com/\(item.streamKey).mp3")!
    }
}
