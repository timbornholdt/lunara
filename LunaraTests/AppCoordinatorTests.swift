import Foundation
import Observation
import Testing
@testable import Lunara

@MainActor
struct AppCoordinatorTests {
    @Test
    func pausePlayback_delegatesToRouterQueuePause() {
        let subject = makeSubject()

        subject.coordinator.pausePlayback()

        #expect(subject.queue.pauseCallCount == 1)
    }

    @Test
    func resumePlayback_delegatesToRouterQueueResume() {
        let subject = makeSubject()

        subject.coordinator.resumePlayback()

        #expect(subject.queue.resumeCallCount == 1)
    }

    @Test
    func skipToNextTrack_delegatesToRouterQueueSkipToNext() {
        let subject = makeSubject()

        subject.coordinator.skipToNextTrack()

        #expect(subject.queue.skipToNextCallCount == 1)
    }

    @Test
    func stopPlayback_delegatesToRouterQueueClear() {
        let subject = makeSubject()

        subject.coordinator.stopPlayback()

        #expect(subject.queue.clearCallCount == 1)
    }

    private func makeSubject() -> (
        coordinator: AppCoordinator,
        queue: CoordinatorQueueManagerMock
    ) {
        let keychain = MockKeychainHelper()
        let authManager = AuthManager(keychain: keychain, authAPI: nil, debugTokenProvider: { nil })
        let plexClient = PlexAPIClient(
            baseURL: URL(string: "http://localhost:32400")!,
            authManager: authManager,
            session: MockURLSession()
        )
        let library = CoordinatorLibraryRepoMock()
        let playbackEngine = CoordinatorPlaybackEngineMock()
        let queue = CoordinatorQueueManagerMock()
        let appRouter = AppRouter(library: library, queue: queue)
        let coordinator = AppCoordinator(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: library,
            playbackEngine: playbackEngine,
            queueManager: queue,
            appRouter: appRouter
        )

        return (coordinator, queue)
    }
}

@MainActor
private final class CoordinatorLibraryRepoMock: LibraryRepoProtocol {
    func fetchAlbums() async throws -> [Album] {
        []
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        []
    }

    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
}

@MainActor
@Observable
private final class CoordinatorPlaybackEngineMock: PlaybackEngineProtocol {
    var playbackState: PlaybackState = .idle
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentTrackID: String?

    func play(url: URL, trackID: String) { }
    func prepareNext(url: URL, trackID: String) { }
    func pause() { }
    func resume() { }
    func seek(to time: TimeInterval) { }
    func stop() { }
}

@MainActor
@Observable
private final class CoordinatorQueueManagerMock: QueueManagerProtocol {
    var items: [QueueItem] = []
    var currentIndex: Int?
    var currentItem: QueueItem?
    var lastError: MusicError?

    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var skipToNextCallCount = 0
    private(set) var clearCallCount = 0

    func playNow(_ items: [QueueItem]) { }
    func playNext(_ items: [QueueItem]) { }
    func playLater(_ items: [QueueItem]) { }
    func play() { }

    func pause() {
        pauseCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }

    func skipToNext() {
        skipToNextCallCount += 1
    }

    func clear() {
        clearCallCount += 1
    }
}
