import Foundation
import Testing
@testable import Lunara

@MainActor
struct CollectionsListViewModelTests {
    @Test
    func loadInitialIfNeeded_loadsCollectionsAndMarksLoaded() async {
        let subject = makeSubject()
        subject.library.stubbedCollections = [
            makeCollection(id: "col-1", title: "Jazz Essentials"),
            makeCollection(id: "col-2", title: "Ambient Chill")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.library.collectionsCallCount == 1)
        #expect(subject.viewModel.collections.map(\.plexID) == ["col-2", "col-1"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadInitialIfNeeded_sortsByTitleAlphabetically() async {
        let subject = makeSubject()
        subject.library.stubbedCollections = [
            makeCollection(id: "col-z", title: "Zebra"),
            makeCollection(id: "col-a", title: "Alpha"),
            makeCollection(id: "col-m", title: "Middle")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.collections.map(\.title) == ["Alpha", "Middle", "Zebra"])
    }

    @Test
    func loadInitialIfNeeded_whenFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.collectionsError = .timeout

        await subject.viewModel.loadInitialIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func pinnedCollections_filtersCorrectly() async {
        let subject = makeSubject()
        subject.library.stubbedCollections = [
            makeCollection(id: "col-1", title: "Current Vibes"),
            makeCollection(id: "col-2", title: "Jazz"),
            makeCollection(id: "col-3", title: "The Key Albums")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.pinnedCollections.map(\.plexID) == ["col-1", "col-3"])
        #expect(subject.viewModel.unpinnedCollections.map(\.plexID) == ["col-2"])
    }

    @Test
    func search_queriesLibraryAndUpdatesResults() async {
        let subject = makeSubject()
        subject.library.stubbedCollections = [
            makeCollection(id: "col-1", title: "Jazz"),
            makeCollection(id: "col-2", title: "Rock")
        ]
        subject.library.searchCollectionsResults["jazz"] = [
            makeCollection(id: "col-1", title: "Jazz")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "jazz"
        await waitForSearch(on: subject.library, expectedCount: 1)

        #expect(subject.viewModel.pinnedCollections.isEmpty)
        #expect(subject.viewModel.unpinnedCollections.map(\.plexID) == ["col-1"])
    }

    @Test
    func search_whenWhitespace_returnsAllCollections() async {
        let subject = makeSubject()
        subject.library.stubbedCollections = [
            makeCollection(id: "col-1", title: "Jazz"),
            makeCollection(id: "col-2", title: "Rock")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "   "

        #expect(subject.viewModel.unpinnedCollections.count == 2)
    }

    private func makeSubject() -> (
        viewModel: CollectionsListViewModel,
        library: CollectionsRepoMock,
        artwork: ArtworkPipelineMock,
        actions: CollectionsActionsMock
    ) {
        let library = CollectionsRepoMock()
        let artwork = ArtworkPipelineMock()
        let actions = CollectionsActionsMock()
        let viewModel = CollectionsListViewModel(
            library: library,
            artworkPipeline: artwork,
            actions: actions
        )

        return (viewModel, library, artwork, actions)
    }

    private func makeCollection(
        id: String,
        title: String = "Collection",
        albumCount: Int = 5
    ) -> Collection {
        Collection(
            plexID: id,
            title: title,
            thumbURL: nil,
            summary: nil,
            albumCount: albumCount,
            updatedAt: nil
        )
    }

    private func waitForSearch(on library: CollectionsRepoMock, expectedCount: Int) async {
        for _ in 0..<80 {
            if library.searchCollectionsCallCount >= expectedCount {
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class CollectionsRepoMock: LibraryRepoProtocol {
    var stubbedCollections: [Collection] = []
    var collectionsCallCount = 0
    var collectionsError: LibraryError?
    var searchCollectionsResults: [String: [Collection]] = [:]
    var searchCollectionsCallCount = 0
    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]
    var tracksByAlbumID: [String: [Track]] = [:]

    func collections() async throws -> [Collection] {
        collectionsCallCount += 1
        if let collectionsError {
            throw collectionsError
        }
        return stubbedCollections
    }

    func collection(id: String) async throws -> Collection? {
        stubbedCollections.first { $0.plexID == id }
    }

    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }

    func searchCollections(query: String) async throws -> [Collection] {
        searchCollectionsCallCount += 1
        return searchCollectionsResults[query] ?? []
    }

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        queriedAlbumsByFilter[filter] ?? []
    }
    func tracks(forAlbum albumID: String) async throws -> [Track] {
        tracksByAlbumID[albumID] ?? []
    }
    func track(id: String) async throws -> Track? { nil }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(timeIntervalSince1970: 0), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        guard let rawValue else { return nil }
        return URL(string: rawValue)
    }
}

@MainActor
private final class CollectionsActionsMock: CollectionsListActionRouting {
    var playCollectionRequests: [String] = []
    var shuffleCollectionRequests: [String] = []
    var playAlbumRequests: [String] = []
    var playCollectionError: Error?
    var shuffleCollectionError: Error?

    func playCollection(_ collection: Collection) async throws {
        playCollectionRequests.append(collection.plexID)
        if let playCollectionError { throw playCollectionError }
    }
    func shuffleCollection(_ collection: Collection) async throws {
        shuffleCollectionRequests.append(collection.plexID)
        if let shuffleCollectionError { throw shuffleCollectionError }
    }
    func playAlbum(_ album: Album) async throws {
        playAlbumRequests.append(album.plexID)
    }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
