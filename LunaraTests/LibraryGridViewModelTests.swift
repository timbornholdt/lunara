import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryGridViewModelTests {
    @Test
    func loadInitialIfNeeded_loadsFirstPageAndMarksLoaded() async throws {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.library.albumPageRequests == [LibraryPage(number: 1, size: 2)])
        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1", "album-2"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadInitialIfNeeded_whenFirstPageFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.errorByPage[1] = .timeout

        await subject.viewModel.loadInitialIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func loadNextPageIfNeeded_whenAtPrefetchThreshold_fetchesAndAppendsPage() async {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [
            makeAlbum(id: "album-1"),
            makeAlbum(id: "album-2")
        ]
        subject.library.albumsByPage[2] = [
            makeAlbum(id: "album-3")
        ]

        await subject.viewModel.loadInitialIfNeeded()
        await subject.viewModel.loadNextPageIfNeeded(currentAlbumID: "album-2")

        #expect(subject.library.albumPageRequests == [
            LibraryPage(number: 1, size: 2),
            LibraryPage(number: 2, size: 2)
        ])
        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1", "album-2", "album-3"])
    }

    @Test
    func loadNextPageIfNeeded_whenNotNearEnd_doesNotFetchNextPage() async {
        let subject = makeSubject(prefetchThreshold: 1)
        subject.library.albumsByPage[1] = [
            makeAlbum(id: "album-1"),
            makeAlbum(id: "album-2"),
            makeAlbum(id: "album-3")
        ]

        await subject.viewModel.loadInitialIfNeeded()
        await subject.viewModel.loadNextPageIfNeeded(currentAlbumID: "album-1")

        #expect(subject.library.albumPageRequests == [LibraryPage(number: 1, size: 2)])
    }

    @Test
    func refresh_clearsAndReloadsFromFirstPage() async {
        let subject = makeSubject()
        subject.library.albumsByPage[1] = [makeAlbum(id: "stale")]

        await subject.viewModel.loadInitialIfNeeded()

        subject.library.albumsByPage[1] = [makeAlbum(id: "fresh")]
        await subject.viewModel.refresh()

        #expect(subject.library.albumPageRequests == [
            LibraryPage(number: 1, size: 2),
            LibraryPage(number: 1, size: 2)
        ])
        #expect(subject.viewModel.albums.map(\.plexID) == ["fresh"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func playAlbum_routesIntentThroughActionsDependency() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-7")

        await subject.viewModel.playAlbum(album)

        #expect(subject.actions.playAlbumRequests == ["album-7"])
        #expect(subject.viewModel.errorBannerState.message == nil)
    }

    @Test
    func playAlbum_whenActionThrows_showsErrorBanner() async {
        let subject = makeSubject()
        subject.actions.playAlbumError = MusicError.trackUnavailable

        await subject.viewModel.playAlbum(makeAlbum(id: "album-err"))

        #expect(subject.actions.playAlbumRequests == ["album-err"])
        #expect(subject.viewModel.errorBannerState.message == MusicError.trackUnavailable.userMessage)
    }

    @Test
    func loadThumbnailIfNeeded_requestsArtworkPipelineAndStoresResolvedURL() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-art", thumbURL: "https://example.com/art.jpg")
        let fileURL = try #require(URL(string: "file:///tmp/album-art.jpg"))
        subject.artwork.thumbnailResultByOwnerID[album.plexID] = fileURL

        subject.viewModel.loadThumbnailIfNeeded(for: album)
        await waitForArtworkResolution(on: subject.viewModel, albumID: album.plexID)

        #expect(subject.artwork.thumbnailRequests == [
            ArtworkPipelineMock.FetchRequest(ownerID: "album-art", ownerKind: .album, sourceURL: URL(string: "https://example.com/art.jpg"))
        ])
        #expect(subject.viewModel.thumbnailURL(for: "album-art") == fileURL)
    }

    @Test
    func loadThumbnailIfNeeded_withRelativeThumb_usesLibraryResolvedAuthenticatedURL() async throws {
        let subject = makeSubject()
        let relativeThumb = "/library/metadata/94303/thumb/1770113059"
        let authenticatedURL = try #require(URL(string: "http://localhost:32400/library/metadata/94303/thumb/1770113059?X-Plex-Token=test"))
        let album = makeAlbum(id: "album-rel", thumbURL: relativeThumb)
        let fileURL = try #require(URL(string: "file:///tmp/album-rel.jpg"))
        subject.library.authenticatedArtworkURLByRawValue[relativeThumb] = authenticatedURL
        subject.artwork.thumbnailResultByOwnerID[album.plexID] = fileURL

        subject.viewModel.loadThumbnailIfNeeded(for: album)
        await waitForArtworkResolution(on: subject.viewModel, albumID: album.plexID)

        #expect(subject.library.authenticatedArtworkURLRequests == [relativeThumb])
        #expect(subject.artwork.thumbnailRequests == [
            ArtworkPipelineMock.FetchRequest(ownerID: "album-rel", ownerKind: .album, sourceURL: authenticatedURL)
        ])
        #expect(subject.viewModel.thumbnailURL(for: "album-rel") == fileURL)
    }

    @Test
    func makeAlbumDetailViewModel_mapsAlbumAndGenreForNavigationDestination() {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-detail")
        let albumWithGenre = Album(
            plexID: album.plexID,
            title: album.title,
            artistName: album.artistName,
            year: album.year,
            thumbURL: album.thumbURL,
            genre: "Trip-Hop",
            rating: album.rating,
            addedAt: album.addedAt,
            trackCount: album.trackCount,
            duration: album.duration
        )

        let detailViewModel = subject.viewModel.makeAlbumDetailViewModel(for: albumWithGenre)

        #expect(detailViewModel.album.plexID == albumWithGenre.plexID)
        #expect(detailViewModel.genres == ["Trip-Hop"])
        #expect(detailViewModel.review == nil)
        #expect(detailViewModel.styles.isEmpty)
        #expect(detailViewModel.moods.isEmpty)
    }

    private func makeSubject(prefetchThreshold: Int = 2) -> (
        viewModel: LibraryGridViewModel,
        library: LibraryGridRepoMock,
        artwork: ArtworkPipelineMock,
        actions: LibraryGridActionsMock
    ) {
        let library = LibraryGridRepoMock()
        let artwork = ArtworkPipelineMock()
        let actions = LibraryGridActionsMock()
        let viewModel = LibraryGridViewModel(
            library: library,
            artworkPipeline: artwork,
            actions: actions,
            pageSize: 2,
            prefetchThreshold: prefetchThreshold
        )

        return (viewModel, library, artwork, actions)
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
            trackCount: 10,
            duration: 1800
        )
    }

    private func waitForArtworkResolution(on viewModel: LibraryGridViewModel, albumID: String) async {
        for _ in 0..<50 {
            if viewModel.thumbnailURL(for: albumID) != nil {
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class LibraryGridRepoMock: LibraryRepoProtocol {
    var albumsByPage: [Int: [Album]] = [:]
    var errorByPage: [Int: LibraryError] = [:]
    var albumPageRequests: [LibraryPage] = []
    var authenticatedArtworkURLByRawValue: [String: URL] = [:]
    var authenticatedArtworkURLRequests: [String?] = []

    func albums(page: LibraryPage) async throws -> [Album] {
        albumPageRequests.append(page)
        if let error = errorByPage[page.number] {
            throw error
        }
        return albumsByPage[page.number] ?? []
    }

    func album(id: String) async throws -> Album? {
        nil
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        []
    }

    func collections() async throws -> [Collection] {
        []
    }

    func artists() async throws -> [Artist] {
        []
    }

    func artist(id: String) async throws -> Artist? {
        nil
    }

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

    func lastRefreshDate() async throws -> Date? {
        nil
    }

    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        authenticatedArtworkURLRequests.append(rawValue)
        guard let rawValue else {
            return nil
        }
        if let mappedURL = authenticatedArtworkURLByRawValue[rawValue] {
            return mappedURL
        }
        return URL(string: rawValue)
    }
}

@MainActor
private final class LibraryGridActionsMock: LibraryGridActionRouting {
    var playAlbumRequests: [String] = []
    var playAlbumError: Error?

    func playAlbum(_ album: Album) async throws {
        playAlbumRequests.append(album.plexID)
        if let playAlbumError {
            throw playAlbumError
        }
    }

    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
