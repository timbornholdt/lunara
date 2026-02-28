import Foundation
import Testing
@testable import Lunara

@MainActor
struct ArtistsListViewModelTests {
    @Test
    func loadInitialIfNeeded_loadsArtistsAndMarksLoaded() async {
        let subject = makeSubject()
        subject.library.stubbedArtists = [
            makeArtist(id: "art-1", name: "Radiohead"),
            makeArtist(id: "art-2", name: "Bjork")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.library.artistsCallCount == 1)
        #expect(subject.viewModel.artists.map(\.plexID) == ["art-2", "art-1"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadInitialIfNeeded_sortsByEffectiveSortName() async {
        let subject = makeSubject()
        subject.library.stubbedArtists = [
            makeArtist(id: "art-z", name: "Zebra", sortName: "Zebra"),
            makeArtist(id: "art-a", name: "Alpha", sortName: "Alpha"),
            makeArtist(id: "art-m", name: "Middle", sortName: "Middle")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.artists.map(\.name) == ["Alpha", "Middle", "Zebra"])
    }

    @Test
    func loadInitialIfNeeded_whenFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.artistsError = .timeout

        await subject.viewModel.loadInitialIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func sectionedArtists_groupsByFirstLetterOfEffectiveSortName() async {
        let subject = makeSubject()
        subject.library.stubbedArtists = [
            makeArtist(id: "art-1", name: "Radiohead", sortName: "Radiohead"),
            makeArtist(id: "art-2", name: "R.E.M.", sortName: "REM"),
            makeArtist(id: "art-3", name: "Bjork", sortName: "Bjork")
        ]

        await subject.viewModel.loadInitialIfNeeded()

        let sections = subject.viewModel.sectionedArtists
        #expect(sections.count == 2)
        #expect(sections[0].letter == "B")
        #expect(sections[0].artists.map(\.plexID) == ["art-3"])
        #expect(sections[1].letter == "R")
        #expect(Set(sections[1].artists.map(\.plexID)) == Set(["art-1", "art-2"]))
    }

    @Test
    func search_queriesLibraryAndUpdatesResults() async {
        let subject = makeSubject()
        subject.library.stubbedArtists = [
            makeArtist(id: "art-1", name: "Radiohead"),
            makeArtist(id: "art-2", name: "Bjork")
        ]
        subject.library.searchArtistsResults["radiohead"] = [
            makeArtist(id: "art-1", name: "Radiohead")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "radiohead"
        await waitForSearch(on: subject.library, expectedCount: 1)

        let sections = subject.viewModel.sectionedArtists
        #expect(sections.count == 1)
        #expect(sections[0].artists.map(\.plexID) == ["art-1"])
    }

    @Test
    func search_whenWhitespace_returnsAllArtists() async {
        let subject = makeSubject()
        subject.library.stubbedArtists = [
            makeArtist(id: "art-1", name: "Radiohead"),
            makeArtist(id: "art-2", name: "Bjork")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "   "

        #expect(subject.viewModel.sectionedArtists.flatMap(\.artists).count == 2)
    }

    @Test
    func thumbnailURL_returnsCachedURL() async {
        let subject = makeSubject()
        let url = URL(string: "file:///test.jpg")!
        subject.viewModel.artworkByArtistID["art-1"] = url

        #expect(subject.viewModel.thumbnailURL(for: "art-1") == url)
        #expect(subject.viewModel.thumbnailURL(for: "art-2") == nil)
    }

    private func makeSubject() -> (
        viewModel: ArtistsListViewModel,
        library: ArtistsRepoMock,
        artwork: ArtworkPipelineMock,
        actions: ArtistsActionsMock
    ) {
        let library = ArtistsRepoMock()
        let artwork = ArtworkPipelineMock()
        let actions = ArtistsActionsMock()
        let viewModel = ArtistsListViewModel(
            library: library,
            artworkPipeline: artwork,
            actions: actions
        )

        return (viewModel, library, artwork, actions)
    }

    private func makeArtist(
        id: String,
        name: String = "Artist",
        sortName: String? = nil,
        albumCount: Int = 5
    ) -> Artist {
        Artist(
            plexID: id,
            name: name,
            sortName: sortName,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: albumCount
        )
    }

    private func waitForSearch(on library: ArtistsRepoMock, expectedCount: Int) async {
        for _ in 0..<80 {
            if library.searchArtistsCallCount >= expectedCount {
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class ArtistsRepoMock: LibraryRepoProtocol {
    var stubbedArtists: [Artist] = []
    var artistsCallCount = 0
    var artistsError: LibraryError?
    var searchArtistsResults: [String: [Artist]] = [:]
    var searchArtistsCallCount = 0

    func artists() async throws -> [Artist] {
        artistsCallCount += 1
        if let artistsError {
            throw artistsError
        }
        return stubbedArtists
    }

    func artist(id: String) async throws -> Artist? {
        stubbedArtists.first { $0.plexID == id }
    }

    func searchArtists(query: String) async throws -> [Artist] {
        searchArtistsCallCount += 1
        return searchArtistsResults[query] ?? []
    }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }

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
private final class ArtistsActionsMock: ArtistsListActionRouting {
    var playArtistRequests: [String] = []
    var shuffleArtistRequests: [String] = []
    var playArtistError: Error?
    var shuffleArtistError: Error?

    func playArtist(_ artist: Artist) async throws {
        playArtistRequests.append(artist.plexID)
        if let playArtistError { throw playArtistError }
    }
    func shuffleArtist(_ artist: Artist) async throws {
        shuffleArtistRequests.append(artist.plexID)
        if let shuffleArtistError { throw shuffleArtistError }
    }
    func playAlbum(_ album: Album) async throws { }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
