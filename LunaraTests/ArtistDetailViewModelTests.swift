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

    // MARK: - MusicBrainz enrichment (Lunara-uww.6.2 / 6.3)

    @Test
    func loadEnrichment_exposesLinksAndMissingAlbums() async {
        let subject = makeSubject()
        subject.library.artistAlbumsByName[subject.artist.name] = [
            makeAlbum(id: "a1", title: "Navy Blues")
        ]
        await subject.viewModel.loadIfNeeded()

        let client = MusicBrainzClientMock()
        client.enrichmentByArtistName["Test Artist"] = MusicBrainzArtistEnrichment(
            artistID: "mbid-1",
            wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/Test_Artist"),
            homepageURL: nil,
            albums: [
                ExternalReleaseGroup(id: "rg-1", title: "Navy Blues", firstReleaseYear: 1998),
                ExternalReleaseGroup(id: "rg-2", title: "Action Pact", firstReleaseYear: 2003)
            ]
        )

        await subject.viewModel.loadEnrichmentIfNeeded(using: client)

        #expect(subject.viewModel.externalLinks?.wikipediaURL?.absoluteString == "https://en.wikipedia.org/wiki/Test_Artist")
        #expect(subject.viewModel.externalLinks?.musicBrainzURL.absoluteString == "https://musicbrainz.org/artist/mbid-1")
        // "Navy Blues" is in the library; only "Action Pact" is missing.
        #expect(subject.viewModel.missingAlbums.map(\.id) == ["rg-2"])
    }

    @Test
    func loadEnrichment_matchesTitlesIgnoringCaseAndPunctuation() async {
        let subject = makeSubject()
        subject.library.artistAlbumsByName[subject.artist.name] = [
            makeAlbum(id: "a1", title: "One Chord To Another!")
        ]
        await subject.viewModel.loadIfNeeded()

        let client = MusicBrainzClientMock()
        client.enrichmentByArtistName["Test Artist"] = MusicBrainzArtistEnrichment(
            artistID: "mbid-1", wikipediaURL: nil, homepageURL: nil,
            albums: [ExternalReleaseGroup(id: "rg-1", title: "one chord to another", firstReleaseYear: 1996)]
        )

        await subject.viewModel.loadEnrichmentIfNeeded(using: client)

        #expect(subject.viewModel.missingAlbums.isEmpty)
    }

    @Test
    func loadEnrichment_fetchesOnce() async {
        let subject = makeSubject()
        await subject.viewModel.loadIfNeeded()
        let client = MusicBrainzClientMock()

        await subject.viewModel.loadEnrichmentIfNeeded(using: client)
        await subject.viewModel.loadEnrichmentIfNeeded(using: client)

        #expect(client.requests.count == 1)
    }

    /// Lunara-c9w: unowned albums list newest-first so fresh releases surface.
    @Test
    func loadEnrichment_sortsMissingAlbumsNewestFirst() async {
        let subject = makeSubject()
        await subject.viewModel.loadIfNeeded()

        let client = MusicBrainzClientMock()
        client.enrichmentByArtistName["Test Artist"] = MusicBrainzArtistEnrichment(
            artistID: "mbid-1", wikipediaURL: nil, homepageURL: nil,
            albums: [
                ExternalReleaseGroup(id: "rg-old", title: "Old", firstReleaseYear: 1998),
                ExternalReleaseGroup(id: "rg-unknown", title: "Mystery", firstReleaseYear: nil),
                ExternalReleaseGroup(id: "rg-new", title: "New", firstReleaseYear: 2023)
            ]
        )

        await subject.viewModel.loadEnrichmentIfNeeded(using: client)

        #expect(subject.viewModel.missingAlbums.map(\.id) == ["rg-new", "rg-old", "rg-unknown"])
    }

    // MARK: - Upcoming concerts (Lunara-uww.6.4)

    @Test
    func loadConcerts_exposesEventsAndFetchesOnce() async {
        let subject = makeSubject()
        let client = TicketmasterClientMock()
        client.eventsByArtistName["Test Artist"] = [
            ConcertEvent(id: "ev-1", name: "Test Artist", localDate: "2026-07-01", venueName: "First Avenue", cityName: "Minneapolis", url: URL(string: "https://tm.example/ev-1"))
        ]

        await subject.viewModel.loadConcertsIfNeeded(using: client)
        await subject.viewModel.loadConcertsIfNeeded(using: client)

        #expect(subject.viewModel.upcomingConcerts.map(\.id) == ["ev-1"])
        #expect(client.requests == ["Test Artist"])
    }

    @Test
    func loadConcerts_withNilClient_staysEmpty() async {
        let subject = makeSubject()

        await subject.viewModel.loadConcertsIfNeeded(using: nil)

        #expect(subject.viewModel.upcomingConcerts.isEmpty)
    }

    // MARK: - Last.fm bio fallback (Lunara-uww.6.1)

    @Test
    func loadLastFMBio_fillsInWhenPlexSummaryEmpty() async {
        let subject = makeSubject(artistSummary: nil)
        let client = LastFMClientMock()
        client.artistBioByName["Test Artist"] = "From Halifax, Nova Scotia."

        await subject.viewModel.loadLastFMBioIfNeeded(using: client)

        #expect(subject.viewModel.displayBio == "From Halifax, Nova Scotia.")
        #expect(client.artistBioRequests == ["Test Artist"])
    }

    @Test
    func loadLastFMBio_skipsWhenPlexSummaryPresent() async {
        let subject = makeSubject(artistSummary: "A test artist")
        let client = LastFMClientMock()
        client.artistBioByName["Test Artist"] = "Should not be used"

        await subject.viewModel.loadLastFMBioIfNeeded(using: client)

        #expect(subject.viewModel.displayBio == "A test artist")
        #expect(client.artistBioRequests.isEmpty)
    }

    @Test
    func loadLastFMBio_fetchesOnlyOnce() async {
        let subject = makeSubject(artistSummary: nil)
        let client = LastFMClientMock()
        client.artistBioByName["Test Artist"] = "Bio"

        await subject.viewModel.loadLastFMBioIfNeeded(using: client)
        await subject.viewModel.loadLastFMBioIfNeeded(using: client)

        #expect(client.artistBioRequests.count == 1)
    }

    private func makeSubject(
        artistID: String = "artist-1",
        artistName: String = "Test Artist",
        artistSummary: String? = "A test artist"
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
            summary: artistSummary,
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

// MARK: - MusicBrainzClientMock

final class MusicBrainzClientMock: MusicBrainzClientProtocol, @unchecked Sendable {
    var enrichmentByArtistName: [String: MusicBrainzArtistEnrichment] = [:]
    private(set) var requests: [String] = []

    func artistEnrichment(name: String) async throws -> MusicBrainzArtistEnrichment? {
        requests.append(name)
        return enrichmentByArtistName[name]
    }

    func upcomingAlbums(artistName: String) async throws -> [ExternalReleaseGroup] {
        []
    }
}


// MARK: - TicketmasterClientMock

final class TicketmasterClientMock: TicketmasterClientProtocol, @unchecked Sendable {
    var eventsByArtistName: [String: [ConcertEvent]] = [:]
    private(set) var requests: [String] = []

    func upcomingEvents(artistName: String) async throws -> [ConcertEvent] {
        requests.append(artistName)
        return eventsByArtistName[artistName] ?? []
    }
}
