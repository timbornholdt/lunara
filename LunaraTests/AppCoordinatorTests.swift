import Foundation
import Observation
import Testing
@testable import Lunara
@MainActor
struct AppCoordinatorTests {
    @Test
    func loadLibraryOnLaunch_returnsCachedAlbumsImmediately_andRefreshesInBackground() async throws {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [makeAlbum(id: "cached-1")]
        subject.library.refreshHook = {
            subject.library.albumsByPage[1] = [makeAlbum(id: "fresh-1"), makeAlbum(id: "fresh-2")]
        }
        let albums = try await subject.coordinator.loadLibraryOnLaunch()
        #expect(albums.map(\.plexID) == ["cached-1"])
        await waitForRefreshReasons(on: subject.library, expected: [.appLaunch])
        await waitForBackgroundRefreshSuccess(on: subject.coordinator, expected: 1)
        #expect(subject.coordinator.lastBackgroundRefreshDate == Date(timeIntervalSince1970: 0))
        #expect(subject.coordinator.lastBackgroundRefreshErrorMessage == nil)
        #expect(subject.library.albumsByPage[1]?.map(\.plexID) == ["fresh-1", "fresh-2"])
    }
    @Test
    func loadLibraryOnLaunch_whenRefreshFails_returnsCachedAlbums() async throws {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [makeAlbum(id: "cached-1")]
        subject.library.refreshError = LibraryError.timeout
        let albums = try await subject.coordinator.loadLibraryOnLaunch()
        #expect(albums.map(\.plexID) == ["cached-1"])
        await waitForRefreshReasons(on: subject.library, expected: [.appLaunch])
        await waitForBackgroundRefreshFailure(on: subject.coordinator, expected: 1)
        #expect(subject.coordinator.lastBackgroundRefreshErrorMessage == LibraryError.timeout.userMessage)
    }
    @Test
    func loadLibraryOnLaunch_whenRefreshFailsAndCacheEmpty_throwsRefreshError() async {
        let subject = makeSubject()
        subject.library.refreshError = LibraryError.timeout
        do {
            _ = try await subject.coordinator.loadLibraryOnLaunch()
            Issue.record("Expected loadLibraryOnLaunch to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }
    }
    @Test
    func fetchAlbums_returnsCachedAlbumsImmediately_andRefreshesInBackground() async throws {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [makeAlbum(id: "cached-1")]
        subject.library.refreshHook = {
            subject.library.albumsByPage[1] = [makeAlbum(id: "fresh-1"), makeAlbum(id: "fresh-2")]
        }
        let albums = try await subject.coordinator.fetchAlbums()
        #expect(albums.map(\.plexID) == ["cached-1"])
        await waitForRefreshReasons(on: subject.library, expected: [.userInitiated])
        await waitForBackgroundRefreshSuccess(on: subject.coordinator, expected: 1)
        #expect(subject.coordinator.lastBackgroundRefreshDate == Date(timeIntervalSince1970: 0))
        #expect(subject.coordinator.lastBackgroundRefreshErrorMessage == nil)
        #expect(subject.library.albumsByPage[1]?.map(\.plexID) == ["fresh-1", "fresh-2"])
    }
    @Test
    func fetchAlbums_whenRefreshFails_returnsCachedAlbums() async throws {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [makeAlbum(id: "cached-1")]
        subject.library.refreshError = LibraryError.timeout
        let albums = try await subject.coordinator.fetchAlbums()
        #expect(albums.map(\.plexID) == ["cached-1"])
        await waitForRefreshReasons(on: subject.library, expected: [.userInitiated])
        await waitForBackgroundRefreshFailure(on: subject.coordinator, expected: 1)
        #expect(subject.coordinator.lastBackgroundRefreshErrorMessage == LibraryError.timeout.userMessage)
    }
    @Test
    func fetchAlbums_whenRefreshFailsAndCacheEmpty_throwsRefreshError() async {
        let subject = makeSubject()
        subject.library.refreshError = LibraryError.timeout
        do {
            _ = try await subject.coordinator.fetchAlbums()
            Issue.record("Expected fetchAlbums to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }
    }
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
    @Test
    func fetchAlbums_withConcreteLibraryRepo_refreshesAndPreloadsArtwork() async throws {
        let keychain = MockKeychainHelper()
        let authManager = AuthManager(keychain: keychain, authAPI: nil, debugTokenProvider: { nil })
        let plexClient = PlexAPIClient(
            baseURL: URL(string: "http://localhost:32400")!,
            authManager: authManager,
            session: MockURLSession()
        )
        let remote = LibraryRemoteMock()
        let store = LibraryStoreMock()
        let artworkPipeline = ArtworkPipelineMock()
        let now = Date(timeIntervalSince1970: 123)
        let repo = LibraryRepo(remote: remote, store: store, artworkPipeline: artworkPipeline, nowProvider: { now })
        let queue = CoordinatorQueueManagerMock()
        let coordinator = AppCoordinator(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: repo,
            artworkPipeline: artworkPipeline,
            playbackEngine: CoordinatorPlaybackEngineMock(),
            queueManager: queue,
            appRouter: AppRouter(library: repo, queue: queue)
        )
        remote.albums = [
            makeAlbum(id: "fresh-1", thumbURL: "/library/metadata/fresh-1/thumb/1"),
            makeAlbum(id: "fresh-2", thumbURL: "/library/metadata/fresh-2/thumb/1")
        ]
        let albums = try await coordinator.fetchAlbums()
        #expect(albums.map(\.plexID) == ["fresh-1", "fresh-2"])
        #expect(store.replaceLibraryCallCount == 0)
        #expect(store.begunSyncRuns.count == 1)
        #expect(store.upsertAlbumsCalls.count == 1)
        #expect(store.completeIncrementalSyncCalls.count == 1)
        await waitForArtworkRequests(
            on: artworkPipeline,
            expectedOwnerIDs: ["fresh-1", "fresh-2"]
        )
        #expect(artworkPipeline.thumbnailRequests.map(\.ownerID) == ["fresh-1", "fresh-2"])
    }
    private func makeSubject() -> (
        coordinator: AppCoordinator,
        queue: CoordinatorQueueManagerMock,
        library: CoordinatorLibraryRepoMock,
        artworkPipeline: ArtworkPipelineMock
    ) {
        let keychain = MockKeychainHelper()
        let authManager = AuthManager(keychain: keychain, authAPI: nil, debugTokenProvider: { nil })
        let plexClient = PlexAPIClient(
            baseURL: URL(string: "http://localhost:32400")!,
            authManager: authManager,
            session: MockURLSession()
        )
        let library = CoordinatorLibraryRepoMock()
        let artworkPipeline = ArtworkPipelineMock()
        let playbackEngine = CoordinatorPlaybackEngineMock()
        let queue = CoordinatorQueueManagerMock()
        let appRouter = AppRouter(library: library, queue: queue)
        let coordinator = AppCoordinator(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: library,
            artworkPipeline: artworkPipeline,
            playbackEngine: playbackEngine,
            queueManager: queue,
            appRouter: appRouter
        )
        return (coordinator, queue, library, artworkPipeline)
    }
    private func makeAlbum(id: String, thumbURL: String? = nil) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: nil,
            thumbURL: thumbURL,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 1,
            duration: 180
        )
    }
    private func waitForArtworkRequests(
        on pipeline: ArtworkPipelineMock,
        expectedOwnerIDs: [String]
    ) async {
        for _ in 0..<50 {
            if pipeline.thumbnailRequests.map(\.ownerID) == expectedOwnerIDs {
                return
            }
            await Task.yield()
        }
    }

    private func waitForRefreshReasons(
        on repo: CoordinatorLibraryRepoMock,
        expected: [LibraryRefreshReason]
    ) async {
        for _ in 0..<80 {
            if repo.refreshReasons == expected {
                return
            }
            await Task.yield()
        }
    }

    private func waitForBackgroundRefreshSuccess(
        on coordinator: AppCoordinator,
        expected: Int
    ) async {
        for _ in 0..<80 {
            if coordinator.backgroundRefreshSuccessToken == expected {
                return
            }
            await Task.yield()
        }
    }

    private func waitForBackgroundRefreshFailure(
        on coordinator: AppCoordinator,
        expected: Int
    ) async {
        for _ in 0..<80 {
            if coordinator.backgroundRefreshFailureToken == expected {
                return
            }
            await Task.yield()
        }
    }
}
@MainActor
private final class CoordinatorLibraryRepoMock: LibraryRepoProtocol {
    var albumsByPage: [Int: [Album]] = [:]
    var refreshReasons: [LibraryRefreshReason] = []
    var refreshError: LibraryError?
    var refreshHook: (() -> Void)?
    func albums(page: LibraryPage) async throws -> [Album] {
        albumsByPage[page.number] ?? []
    }
    func album(id: String) async throws -> Album? {
        nil
    }
    func searchAlbums(query: String) async throws -> [Album] {
        []
    }
    func tracks(forAlbum albumID: String) async throws -> [Track] {
        []
    }
    func track(id: String) async throws -> Track? {
        nil
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: albumByID(albumID), tracks: tracksByAlbumID(albumID))
    }
    func collections() async throws -> [Collection] {
        []
    }
    func collection(id: String) async throws -> Collection? {
        nil
    }
    func searchCollections(query: String) async throws -> [Collection] {
        []
    }
    func artists() async throws -> [Artist] {
        []
    }
    func artist(id: String) async throws -> Artist? {
        nil
    }
    func searchArtists(query: String) async throws -> [Artist] {
        []
    }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        refreshReasons.append(reason)
        if let refreshError {
            throw refreshError
        }
        refreshHook?()
        return LibraryRefreshOutcome(
            reason: reason,
            refreshedAt: Date(timeIntervalSince1970: 0),
            albumCount: 0,
            trackCount: 0,
            artistCount: 0,
            collectionCount: 0
        )
    }
    func lastRefreshDate() async throws -> Date? {
        nil
    }
    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        nil
    }

    private func albumByID(_ albumID: String) -> Album? {
        albumsByPage.values.flatMap { $0 }.first { $0.plexID == albumID }
    }

    private func tracksByAlbumID(_ albumID: String) -> [Track] {
        []
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
