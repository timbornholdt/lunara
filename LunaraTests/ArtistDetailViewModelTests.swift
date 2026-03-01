import Foundation
import Testing
@testable import Lunara

@MainActor
struct ArtistDetailViewModelTests {
    @Test
    func loadIfNeeded_fetchesAlbumsForArtistAndMarksLoaded() async {
        let subject = makeSubject()
        subject.library.artistAlbumsByName[subject.artist.name] = [
            makeAlbum(id: "album-1", year: 1997),
            makeAlbum(id: "album-2", year: 2005),
            makeAlbum(id: "album-3", year: nil)
        ]

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1", "album-2", "album-3"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadIfNeeded_whenFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.artistAlbumsError = .timeout

        await subject.viewModel.loadIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func playAll_routesThroughActions() async {
        let subject = makeSubject()

        await subject.viewModel.playAll()

        #expect(subject.actions.playArtistRequests == [subject.artist.plexID])
    }

    @Test
    func shuffle_routesThroughActions() async {
        let subject = makeSubject()

        await subject.viewModel.shuffle()

        #expect(subject.actions.shuffleArtistRequests == [subject.artist.plexID])
    }

    @Test
    func playAll_whenThrows_showsErrorBanner() async {
        let subject = makeSubject()
        subject.actions.playArtistError = MusicError.trackUnavailable

        await subject.viewModel.playAll()

        #expect(subject.viewModel.errorBannerState.message == MusicError.trackUnavailable.userMessage)
    }

    @Test
    func shuffle_whenThrows_showsErrorBanner() async {
        let subject = makeSubject()
        subject.actions.shuffleArtistError = MusicError.trackUnavailable

        await subject.viewModel.shuffle()

        #expect(subject.viewModel.errorBannerState.message == MusicError.trackUnavailable.userMessage)
    }

    @Test
    func playAlbum_routesThroughActions() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-play")

        await subject.viewModel.playAlbum(album)

        #expect(subject.actions.playAlbumRequests == ["album-play"])
    }

    private func makeSubject(
        artistID: String = "artist-1",
        artistName: String = "Test Artist"
    ) -> (
        viewModel: ArtistDetailViewModel,
        artist: Artist,
        library: ArtistDetailRepoMock,
        artwork: ArtworkPipelineMock,
        actions: ArtistDetailActionsMock
    ) {
        let artist = Artist(
            plexID: artistID,
            name: artistName,
            sortName: nil,
            thumbURL: nil,
            genre: "Rock",
            summary: "A test artist",
            albumCount: 5
        )
        let library = ArtistDetailRepoMock()
        let artwork = ArtworkPipelineMock()
        let actions = ArtistDetailActionsMock()
        let viewModel = ArtistDetailViewModel(
            artist: artist,
            library: library,
            artworkPipeline: artwork,
            actions: actions
        )

        return (viewModel, artist, library, artwork, actions)
    }

    private func makeAlbum(id: String, title: String? = nil, year: Int? = nil) -> Album {
        Album(
            plexID: id,
            title: title ?? "Album \(id)",
            artistName: "Artist",
            year: year,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 10,
            duration: 1800
        )
    }
}

@MainActor
private final class ArtistDetailRepoMock: LibraryRepoProtocol {
    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]
    var queryAlbumsError: LibraryError?

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        if let queryAlbumsError { throw queryAlbumsError }
        return queriedAlbumsByFilter[filter] ?? []
    }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func track(id: String) async throws -> Track? { nil }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    var artistAlbumsByName: [String: [Album]] = [:]
    var artistAlbumsError: LibraryError?
    func artistAlbums(artistName: String) async throws -> [Album] {
        if let artistAlbumsError { throw artistAlbumsError }
        return artistAlbumsByName[artistName] ?? []
    }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }
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
private final class ArtistDetailActionsMock: ArtistsListActionRouting {
    var playArtistRequests: [String] = []
    var shuffleArtistRequests: [String] = []
    var playAlbumRequests: [String] = []
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
