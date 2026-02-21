import Foundation
import Testing
@testable import Lunara

@MainActor
struct AlbumDetailViewModelTests {
    @Test
    func loadIfNeeded_fetchesAlbumTracks() async {
        let subject = makeSubject()
        subject.library.tracksByAlbumID[subject.album.plexID] = [
            makeTrack(id: "track-1", albumID: subject.album.plexID),
            makeTrack(id: "track-2", albumID: subject.album.plexID)
        ]

        await subject.viewModel.loadIfNeeded()

        #expect(subject.library.trackRequests == [subject.album.plexID])
        #expect(subject.viewModel.tracks.map(\.plexID) == ["track-1", "track-2"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadIfNeeded_fetchesAndAppliesAlbumMetadataFromLibrary() async {
        let subject = makeSubject(review: nil, genres: nil, styles: [], moods: [])
        subject.library.albumByID[subject.album.plexID] = Album(
            plexID: subject.album.plexID,
            title: subject.album.title,
            artistName: subject.album.artistName,
            year: subject.album.year,
            thumbURL: subject.album.thumbURL,
            genre: "Pop/Rock",
            rating: subject.album.rating,
            addedAt: subject.album.addedAt,
            trackCount: subject.album.trackCount,
            duration: subject.album.duration,
            review: "Imported review",
            genres: ["Pop/Rock"],
            styles: ["Contemporary Pop/Rock"],
            moods: ["Brooding"]
        )

        await subject.viewModel.loadIfNeeded()

        #expect(subject.library.albumRequests == [subject.album.plexID])
        #expect(subject.viewModel.review == "Imported review")
        #expect(subject.viewModel.genres == ["Pop/Rock"])
        #expect(subject.viewModel.styles == ["Contemporary Pop/Rock"])
        #expect(subject.viewModel.moods == ["Brooding"])
    }

    @Test
    func loadIfNeeded_backgroundRefreshAppliesUpdatedMetadataAndTracks() async {
        let subject = makeSubject(review: nil, genres: nil, styles: [], moods: [])
        let cachedTrack = makeTrack(id: "track-cached", albumID: subject.album.plexID)
        subject.library.tracksByAlbumID[subject.album.plexID] = [cachedTrack]
        subject.library.refreshOutcomeByAlbumID[subject.album.plexID] = AlbumDetailRefreshOutcome(
            album: Album(
                plexID: subject.album.plexID,
                title: subject.album.title,
                artistName: subject.album.artistName,
                year: subject.album.year,
                thumbURL: subject.album.thumbURL,
                genre: "Jazz",
                rating: subject.album.rating,
                addedAt: subject.album.addedAt,
                trackCount: subject.album.trackCount,
                duration: subject.album.duration,
                review: "Fresh review",
                genres: ["Jazz"],
                styles: ["Post-Bop"],
                moods: ["Driving"]
            ),
            tracks: [makeTrack(id: "track-fresh", albumID: subject.album.plexID)]
        )

        await subject.viewModel.loadIfNeeded()
        await waitForBackgroundRefresh(on: subject.library, expectedAlbumID: subject.album.plexID)

        #expect(subject.viewModel.review == "Fresh review")
        #expect(subject.viewModel.genres == ["Jazz"])
        #expect(subject.viewModel.styles == ["Post-Bop"])
        #expect(subject.viewModel.moods == ["Driving"])
        #expect(subject.viewModel.tracks.map(\.plexID) == ["track-fresh"])
    }

    @Test
    func playAlbum_routesIntentToActions() async {
        let subject = makeSubject()

        await subject.viewModel.playAlbum()

        #expect(subject.actions.playAlbumRequests == [subject.album.plexID])
    }

    @Test
    func queueAlbumNext_routesIntentToActions() async {
        let subject = makeSubject()

        await subject.viewModel.queueAlbumNext()

        #expect(subject.actions.queueAlbumNextRequests == [subject.album.plexID])
    }

    @Test
    func queueAlbumLater_routesIntentToActions() async {
        let subject = makeSubject()

        await subject.viewModel.queueAlbumLater()

        #expect(subject.actions.queueAlbumLaterRequests == [subject.album.plexID])
    }

    @Test
    func playTrackNow_routesIntentToActions() async {
        let subject = makeSubject()
        let track = makeTrack(id: "track-now", albumID: subject.album.plexID)

        await subject.viewModel.playTrackNow(track)

        #expect(subject.actions.playTrackNowRequests == [track.plexID])
    }

    @Test
    func queueTrackNext_routesIntentToActions() async {
        let subject = makeSubject()
        let track = makeTrack(id: "track-next", albumID: subject.album.plexID)

        await subject.viewModel.queueTrackNext(track)

        #expect(subject.actions.queueTrackNextRequests == [track.plexID])
    }

    @Test
    func queueTrackLater_routesIntentToActions() async {
        let subject = makeSubject()
        let track = makeTrack(id: "track-later", albumID: subject.album.plexID)

        await subject.viewModel.queueTrackLater(track)

        #expect(subject.actions.queueTrackLaterRequests == [track.plexID])
    }

    private func makeSubject(
        review: String? = "A detailed review",
        genres: [String]? = ["Ambient", "Electronic"],
        styles: [String] = ["Downtempo"],
        moods: [String] = ["Calm"]
    ) -> (
        viewModel: AlbumDetailViewModel,
        album: Album,
        library: AlbumDetailLibraryRepoMock,
        artwork: AlbumDetailArtworkPipelineMock,
        actions: AlbumDetailActionsMock
    ) {
        let album = makeAlbum(id: "album-1")
        let library = AlbumDetailLibraryRepoMock()
        let artwork = AlbumDetailArtworkPipelineMock()
        let actions = AlbumDetailActionsMock()
        let viewModel = AlbumDetailViewModel(
            album: album,
            library: library,
            artworkPipeline: artwork,
            actions: actions,
            review: review,
            genres: genres,
            styles: styles,
            moods: moods
        )
        return (viewModel, album, library, artwork, actions)
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: 2025,
            thumbURL: nil,
            genre: "Electronic",
            rating: nil,
            addedAt: nil,
            trackCount: 10,
            duration: 1800
        )
    }

    private func makeTrack(id: String, albumID: String) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: 1,
            duration: 200,
            artistName: "Artist",
            key: "/library/parts/\(id).mp3",
            thumbURL: nil
        )
    }
}

@MainActor
private final class AlbumDetailLibraryRepoMock: LibraryRepoProtocol {
    var albumByID: [String: Album] = [:]
    var albumRequests: [String] = []
    var tracksByAlbumID: [String: [Track]] = [:]
    var trackRequests: [String] = []
    var refreshOutcomeByAlbumID: [String: AlbumDetailRefreshOutcome] = [:]
    var refreshAlbumDetailRequests: [String] = []

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? {
        albumRequests.append(id)
        return albumByID[id]
    }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        trackRequests.append(albumID)
        return tracksByAlbumID[albumID] ?? []
    }
    func track(id: String) async throws -> Track? { nil }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        refreshAlbumDetailRequests.append(albumID)
        return refreshOutcomeByAlbumID[albumID] ?? AlbumDetailRefreshOutcome(
            album: albumByID[albumID],
            tracks: tracksByAlbumID[albumID] ?? []
        )
    }

    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(
            reason: reason,
            refreshedAt: Date(timeIntervalSince1970: 0),
            albumCount: 0,
            trackCount: 0,
            artistCount: 0,
            collectionCount: 0
        )
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? { nil }
}

@MainActor
private final class AlbumDetailArtworkPipelineMock: ArtworkPipelineProtocol {
    func fetchThumbnail(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? { nil }
    func fetchFullSize(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? { nil }
    func invalidateCache(for key: ArtworkCacheKey) async throws { }
    func invalidateCache(for ownerID: String, ownerKind: ArtworkOwnerKind) async throws { }
    func invalidateAllCache() async throws { }
}

@MainActor
private final class AlbumDetailActionsMock: AlbumDetailActionRouting {
    var playAlbumRequests: [String] = []
    var queueAlbumNextRequests: [String] = []
    var queueAlbumLaterRequests: [String] = []
    var playTrackNowRequests: [String] = []
    var queueTrackNextRequests: [String] = []
    var queueTrackLaterRequests: [String] = []

    func playAlbum(_ album: Album) async throws {
        playAlbumRequests.append(album.plexID)
    }

    func queueAlbumNext(_ album: Album) async throws {
        queueAlbumNextRequests.append(album.plexID)
    }

    func queueAlbumLater(_ album: Album) async throws {
        queueAlbumLaterRequests.append(album.plexID)
    }

    func playTrackNow(_ track: Track) async throws {
        playTrackNowRequests.append(track.plexID)
    }

    func queueTrackNext(_ track: Track) async throws {
        queueTrackNextRequests.append(track.plexID)
    }

    func queueTrackLater(_ track: Track) async throws {
        queueTrackLaterRequests.append(track.plexID)
    }
}

@MainActor
private func waitForBackgroundRefresh(
    on repo: AlbumDetailLibraryRepoMock,
    expectedAlbumID: String
) async {
    for _ in 0..<100 {
        if repo.refreshAlbumDetailRequests.contains(expectedAlbumID) {
            return
        }
        await Task.yield()
    }
}
