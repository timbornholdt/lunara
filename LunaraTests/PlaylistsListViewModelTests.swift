import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaylistsListViewModelTests {
    @Test
    func loadInitialIfNeeded_loadsPlaylistsAndMarksLoaded() async {
        let subject = makeSubject()
        subject.library.stubbedPlaylists = [
            makeSnapshot(id: "pl-1", title: "Jazz Mix"),
            makeSnapshot(id: "pl-2", title: "Ambient")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.library.playlistsCallCount == 1)
        #expect(subject.viewModel.playlists.map(\.plexID) == ["pl-2", "pl-1"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadInitialIfNeeded_sortsByTitleAlphabetically() async {
        let subject = makeSubject()
        subject.library.stubbedPlaylists = [
            makeSnapshot(id: "pl-z", title: "Zebra"),
            makeSnapshot(id: "pl-a", title: "Alpha"),
            makeSnapshot(id: "pl-m", title: "Middle")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.playlists.map(\.title) == ["Alpha", "Middle", "Zebra"])
    }

    @Test
    func loadInitialIfNeeded_whenFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.playlistsError = .timeout

        await subject.viewModel.loadInitialIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func pinnedPlaylists_filtersCorrectly() async {
        let subject = makeSubject()
        subject.library.stubbedPlaylists = [
            makeSnapshot(id: "pl-1", title: "Chopping Block"),
            makeSnapshot(id: "pl-2", title: "Jazz Mix"),
            makeSnapshot(id: "pl-3", title: "Recently Added")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.pinnedPlaylists.map(\.plexID) == ["pl-1", "pl-3"])
        #expect(subject.viewModel.unpinnedPlaylists.map(\.plexID) == ["pl-2"])
    }

    @Test
    func search_queriesLibraryAndUpdatesResults() async {
        let subject = makeSubject()
        subject.library.stubbedPlaylists = [
            makeSnapshot(id: "pl-1", title: "Jazz"),
            makeSnapshot(id: "pl-2", title: "Rock")
        ]
        subject.library.searchPlaylistsResults["jazz"] = [
            makeSnapshot(id: "pl-1", title: "Jazz")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "jazz"
        await waitForSearch(on: subject.library, expectedCount: 1)

        #expect(subject.viewModel.pinnedPlaylists.isEmpty)
        #expect(subject.viewModel.unpinnedPlaylists.map(\.plexID) == ["pl-1"])
    }

    @Test
    func search_whenWhitespace_returnsAllPlaylists() async {
        let subject = makeSubject()
        subject.library.stubbedPlaylists = [
            makeSnapshot(id: "pl-1", title: "Jazz"),
            makeSnapshot(id: "pl-2", title: "Rock")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "   "

        #expect(subject.viewModel.unpinnedPlaylists.count == 2)
    }

    private func makeSubject() -> (
        viewModel: PlaylistsListViewModel,
        library: PlaylistsRepoMock,
        artwork: ArtworkPipelineMock,
        actions: PlaylistsActionsMock
    ) {
        let library = PlaylistsRepoMock()
        let artwork = ArtworkPipelineMock()
        let actions = PlaylistsActionsMock()
        let viewModel = PlaylistsListViewModel(
            library: library,
            artworkPipeline: artwork,
            actions: actions
        )

        return (viewModel, library, artwork, actions)
    }

    private func makeSnapshot(
        id: String,
        title: String = "Playlist",
        trackCount: Int = 10
    ) -> LibraryPlaylistSnapshot {
        LibraryPlaylistSnapshot(
            plexID: id,
            title: title,
            trackCount: trackCount,
            updatedAt: nil,
            thumbURL: nil
        )
    }

    private func waitForSearch(on library: PlaylistsRepoMock, expectedCount: Int) async {
        for _ in 0..<80 {
            if library.searchPlaylistsCallCount >= expectedCount {
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class PlaylistsRepoMock: LibraryRepoProtocol {
    var stubbedPlaylists: [LibraryPlaylistSnapshot] = []
    var playlistsCallCount = 0
    var playlistsError: LibraryError?
    var searchPlaylistsResults: [String: [LibraryPlaylistSnapshot]] = [:]
    var searchPlaylistsCallCount = 0
    var playlistItemsByPlaylistID: [String: [LibraryPlaylistItemSnapshot]] = [:]

    func playlists() async throws -> [LibraryPlaylistSnapshot] {
        playlistsCallCount += 1
        if let playlistsError {
            throw playlistsError
        }
        return stubbedPlaylists
    }

    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] {
        playlistItemsByPlaylistID[playlistID] ?? []
    }

    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] {
        searchPlaylistsCallCount += 1
        return searchPlaylistsResults[query] ?? []
    }

    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func track(id: String) async throws -> Track? { nil }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
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
private final class PlaylistsActionsMock: PlaylistsListActionRouting {
    var playPlaylistRequests: [String] = []
    var shufflePlaylistRequests: [String] = []

    func playPlaylist(_ playlist: Playlist) async throws {
        playPlaylistRequests.append(playlist.plexID)
    }
    func shufflePlaylist(_ playlist: Playlist) async throws {
        shufflePlaylistRequests.append(playlist.plexID)
    }
    func playAlbum(_ album: Album) async throws { }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
