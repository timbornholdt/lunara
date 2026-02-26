import Foundation
import Testing
@testable import Lunara

@MainActor
@Suite
struct NowPlayingBridgeTests {

    @Test
    func configureDoesNotCrash() {
        let engine = PlaybackEngineMock()
        let queue = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        let artwork = ArtworkPipelineMock()
        let bridge = NowPlayingBridge(
            engine: engine,
            queue: queue,
            library: library,
            artwork: artwork
        )
        bridge.configure()
    }

    @Test
    func bridgeCreatesWithAllDependencies() {
        let engine = PlaybackEngineMock()
        let queue = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        let artwork = ArtworkPipelineMock()
        let bridge = NowPlayingBridge(
            engine: engine,
            queue: queue,
            library: library,
            artwork: artwork
        )
        #expect(bridge != nil)
    }
}

// MARK: - Test Doubles

@MainActor
@Observable
final class NowPlayingQueueMock: QueueManagerProtocol {
    var items: [QueueItem] = []
    var currentIndex: Int?
    var currentItem: QueueItem?
    var lastError: MusicError?

    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var skipToNextCallCount = 0
    private(set) var skipBackCallCount = 0
    private(set) var clearCallCount = 0

    func playNow(_ items: [QueueItem]) {}
    func playNext(_ items: [QueueItem]) {}
    func playLater(_ items: [QueueItem]) {}

    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func resume() { resumeCallCount += 1 }
    func skipToNext() { skipToNextCallCount += 1 }
    func skipBack() { skipBackCallCount += 1 }
    func clear() { clearCallCount += 1 }
    func reconcile(removingTrackIDs: Set<String>) {}
}

@MainActor
final class NowPlayingLibraryMock: LibraryRepoProtocol {
    var trackByID: [String: Track] = [:]
    var albumByID: [String: Album] = [:]

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { albumByID[id] }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func track(id: String) async throws -> Track? { trackByID[id] }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL { URL(string: "http://example.com")! }
}
