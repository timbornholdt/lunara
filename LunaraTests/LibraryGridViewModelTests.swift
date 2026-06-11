import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryGridViewModelTests {
    @Test
    func loadInitialIfNeeded_loadsFullCachedCatalogAndMarksLoaded() async throws {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.library.albumQueryFilters == [.all])
        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1", "album-2"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadInitialIfNeeded_whenFirstPageFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.queryErrorByFilter[.all] = .timeout

        await subject.viewModel.loadInitialIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func refresh_forcesLibraryRefreshAndReloadsCachedCatalog() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "stale")]

        await subject.viewModel.loadInitialIfNeeded()

        subject.library.refreshHook = {
            subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "fresh")]
        }
        await subject.viewModel.refresh()

        #expect(subject.library.refreshReasons == [.userInitiated])
        #expect(subject.library.albumQueryFilters == [.all, .all])
        #expect(subject.viewModel.albums.map(\.plexID) == ["fresh"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func applyBackgroundRefreshUpdateIfNeeded_reloadsVisibleCachedPages() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]

        await subject.viewModel.loadInitialIfNeeded()

        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "fresh-1"), makeAlbum(id: "fresh-2")]

        await subject.viewModel.applyBackgroundRefreshUpdateIfNeeded(successToken: 1)

        #expect(subject.viewModel.albums.map(\.plexID) == ["fresh-1", "fresh-2"])
        #expect(subject.library.albumQueryFilters == [.all, .all])
    }

    @Test
    func applyBackgroundRefreshUpdateIfNeeded_withActiveSearch_reloadsSearchResultsFromCatalog() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]
        let blueFilter = AlbumQueryFilter(textQuery: "blue")
        subject.library.queriedAlbumsByFilter[blueFilter] = [makeAlbum(id: "old-result", title: "Old Blue")]

        await subject.viewModel.loadInitialIfNeeded()
        subject.viewModel.searchQuery = "blue"
        await waitForCatalogQueryRequest(on: subject.library, expectedCount: 2)
        #expect(subject.viewModel.filteredAlbums.map(\.plexID) == ["old-result"])

        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "album-3"), makeAlbum(id: "album-4")]
        subject.library.queriedAlbumsByFilter[blueFilter] = [makeAlbum(id: "new-result", title: "New Blue")]

        await subject.viewModel.applyBackgroundRefreshUpdateIfNeeded(successToken: 1)

        #expect(subject.library.albumQueryFilters == [.all, blueFilter, .all, blueFilter])
        #expect(subject.viewModel.filteredAlbums.map(\.plexID) == ["new-result"])
    }

    @Test
    func applyBackgroundRefreshFailureIfNeeded_showsErrorBannerMessage() {
        let subject = makeSubject()

        subject.viewModel.applyBackgroundRefreshFailureIfNeeded(
            failureToken: 1,
            message: "Refresh failed"
        )

        #expect(subject.viewModel.errorBannerState.message == "Refresh failed")
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

    @Test
    func filteredAlbums_whenSearchQueryMatchesTitle_usesCatalogSearchResults() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [
            makeAlbum(id: "album-1", title: "Blue Train", artistName: "John Coltrane"),
            makeAlbum(id: "album-2", title: "Giant Steps", artistName: "John Coltrane")
        ]
        let blueFilter = AlbumQueryFilter(textQuery: "blue")
        subject.library.queriedAlbumsByFilter[blueFilter] = [
            makeAlbum(id: "album-9", title: "Blue", artistName: "Joni Mitchell")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "blue"
        await waitForCatalogQueryRequest(on: subject.library, expectedCount: 2)

        #expect(subject.library.albumQueryFilters == [.all, blueFilter])
        #expect(subject.viewModel.filteredAlbums.map(\.plexID) == ["album-9"])
    }

    @Test
    func filteredAlbums_whenSearchQueryMatchesArtist_usesCatalogSearchResults() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [
            makeAlbum(id: "album-1", title: "Kind of Blue", artistName: "Miles Davis"),
            makeAlbum(id: "album-2", title: "A Love Supreme", artistName: "John Coltrane")
        ]
        let coltraneFilter = AlbumQueryFilter(textQuery: "coltrane")
        subject.library.queriedAlbumsByFilter[coltraneFilter] = [
            makeAlbum(id: "album-4", title: "Crescent", artistName: "John Coltrane")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "coltrane"
        await waitForCatalogQueryRequest(on: subject.library, expectedCount: 2)

        #expect(subject.library.albumQueryFilters == [.all, coltraneFilter])
        #expect(subject.viewModel.filteredAlbums.map(\.plexID) == ["album-4"])
    }

    @Test
    func filteredAlbums_whenSearchQueryIsWhitespace_returnsAllAlbums() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [
            makeAlbum(id: "album-1"),
            makeAlbum(id: "album-2")
        ]
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "   "

        #expect(subject.library.albumQueryFilters == [.all])
        #expect(subject.viewModel.filteredAlbums.map(\.plexID) == ["album-1", "album-2"])
    }

    @Test
    func filteredAlbums_whenCatalogSearchFails_showsErrorBannerAndReturnsNoMatches() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [makeAlbum(id: "album-1", title: "Blue Train")]
        let blueFilter = AlbumQueryFilter(textQuery: "blue")
        subject.library.queryErrorByFilter[blueFilter] = .timeout
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.searchQuery = "blue"
        await waitForCatalogQueryRequest(on: subject.library, expectedCount: 2)

        #expect(subject.viewModel.filteredAlbums.isEmpty)
        #expect(subject.viewModel.errorBannerState.message == LibraryError.timeout.userMessage)
    }

    // MARK: - Keyset pagination (Lunara-uww.4.1)

    // MARK: - Load-all catalog + sorts (Lunara-mam)

    @Test
    func loadInitialIfNeeded_loadsTheWholeCatalogAtOnce() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = makeAlbums(120)

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.albums.count == 120)
        #expect(subject.viewModel.filteredAlbums.count == 120)
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadInitialIfNeeded_emptyCatalog_marksLoaded() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = []

        await subject.viewModel.loadInitialIfNeeded()

        #expect(subject.viewModel.albums.isEmpty)
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func setSort_releaseDate_reordersInMemoryWithoutRefetch() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = [
            makeAlbum(id: "old", year: 1990),
            makeAlbum(id: "new", year: 2024),
            makeAlbum(id: "unknown")
        ]
        await subject.viewModel.loadInitialIfNeeded()
        let baseline = subject.library.albumQueryFilters.count

        subject.viewModel.setSort(.releaseDate)

        #expect(subject.viewModel.filteredAlbums.map(\.plexID) == ["new", "old", "unknown"])
        #expect(subject.library.albumQueryFilters.count == baseline)
    }

    @Test
    func setSort_randomRepicked_reshufflesButKeepsMembership() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = makeAlbums(40)
        await subject.viewModel.loadInitialIfNeeded()

        subject.viewModel.setSort(.random)
        let first = subject.viewModel.filteredAlbums.map(\.plexID)
        subject.viewModel.setSort(.random)
        let second = subject.viewModel.filteredAlbums.map(\.plexID)

        #expect(first.count == 40)
        #expect(Set(first) == Set(second))
        // Fresh seed per pick; identical 40-item orders are ~impossible.
        #expect(first != second)
    }

    @Test
    func sortChoice_persistsToInjectedDefaults() async {
        let defaults = UserDefaults(suiteName: "grid-sort-\(UUID().uuidString)")!
        let subject = makeSubject(sortDefaults: defaults)

        subject.viewModel.setSort(.releaseDate)

        #expect(AlbumGridSort.load(from: defaults) == .releaseDate)
        #expect(subject.viewModel.sort == .releaseDate)
    }

    @Test
    func refresh_reloadsTheWholeCatalog() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = makeAlbums(120)
        await subject.viewModel.loadInitialIfNeeded()

        await subject.viewModel.refresh()

        #expect(subject.viewModel.albums.count == 120)
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func clearingSearch_restoresTheFullSortedCatalog() async {
        let subject = makeSubject()
        subject.library.queriedAlbumsByFilter[.all] = makeAlbums(120)
        await subject.viewModel.loadInitialIfNeeded()

        subject.library.queriedAlbumsByFilter[AlbumQueryFilter(textQuery: "x")] = [makeAlbum(id: "search-hit")]
        subject.viewModel.searchQuery = "x"
        subject.viewModel.searchQuery = ""

        #expect(subject.viewModel.albums.count == 120)
        #expect(subject.viewModel.filteredAlbums.count == 120)
    }

    // MARK: - Artwork LRU cache (Lunara-uww.4.2)

    @Test
    func artworkCache_neverExceedsInjectedCapacity() async {
        let subject = makeSubject(artworkCacheCapacity: 3)

        for i in 0..<8 {
            await resolveArtwork(id: "al-\(i)", subject: subject)
        }

        #expect(subject.viewModel.artworkByAlbumID.count <= 3)
        // The most recently resolved album is retained.
        #expect(subject.viewModel.artworkByAlbumID["al-7"] != nil)
    }

    @Test
    func artworkCache_evictsLeastRecentlyUsedFirst() async {
        let subject = makeSubject(artworkCacheCapacity: 3)
        for i in 0..<3 {
            await resolveArtwork(id: "al-\(i)", subject: subject)
        }

        // Touch the oldest entry so it becomes most-recently-used.
        _ = subject.viewModel.thumbnailURL(for: "al-0")

        // A fourth resolution evicts the least recently USED (al-1), not al-0.
        await resolveArtwork(id: "al-3", subject: subject)

        #expect(subject.viewModel.artworkByAlbumID["al-0"] != nil)
        #expect(subject.viewModel.artworkByAlbumID["al-1"] == nil)
        #expect(subject.viewModel.artworkByAlbumID["al-2"] != nil)
        #expect(subject.viewModel.artworkByAlbumID["al-3"] != nil)
    }

    @Test
    func artworkCache_evictedAlbumReResolvesOnRequest() async {
        let subject = makeSubject(artworkCacheCapacity: 2)
        for i in 0..<3 {
            await resolveArtwork(id: "al-\(i)", subject: subject)
        }
        #expect(subject.viewModel.artworkByAlbumID["al-0"] == nil) // evicted

        // Pending state must not be stuck: a re-request issues a fresh pipeline
        // fetch and re-inserts the artwork.
        let requestsBefore = subject.artwork.thumbnailRequests.filter { $0.ownerID == "al-0" }.count
        await resolveArtwork(id: "al-0", subject: subject)

        #expect(subject.artwork.thumbnailRequests.filter { $0.ownerID == "al-0" }.count == requestsBefore + 1)
        #expect(subject.viewModel.artworkByAlbumID["al-0"] != nil)
    }

    private func triggerItem(_ albums: [Album]) -> Album {
        albums[max(0, albums.count - 10)]
    }

    private func makeAlbums(_ count: Int) -> [Album] {
        (0..<count).map { makeAlbum(id: String(format: "album-%03d", $0)) }
    }

    private func makeSubject(
        artworkCacheCapacity: Int = 300,
        sortDefaults: UserDefaults = UserDefaults(suiteName: "grid-tests-\(UUID().uuidString)")!
    ) -> (
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
            artworkCacheCapacity: artworkCacheCapacity,
            sortDefaults: sortDefaults
        )

        return (viewModel, library, artwork, actions)
    }

    /// Seeds the pipeline mock with a resolvable thumbnail for `id`, requests it,
    /// and waits for it to land in the view model's artwork dictionary.
    private func resolveArtwork(
        id: String,
        subject: (viewModel: LibraryGridViewModel, library: LibraryGridRepoMock, artwork: ArtworkPipelineMock, actions: LibraryGridActionsMock)
    ) async {
        let album = makeAlbum(id: id, thumbURL: "https://plex.example.com/\(id).jpg")
        subject.artwork.thumbnailResultByOwnerID[id] = URL(fileURLWithPath: "/tmp/\(id).jpg")
        subject.viewModel.loadThumbnailIfNeeded(for: album)
        await waitForArtworkResolution(on: subject.viewModel, albumID: id)
    }

    private func makeAlbum(
        id: String,
        title: String? = nil,
        artistName: String? = nil,
        thumbURL: String? = nil,
        year: Int? = nil
    ) -> Album {
        Album(
            plexID: id,
            title: title ?? "Album \(id)",
            artistName: artistName ?? "Artist",
            year: year,
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

    private func waitForCatalogQueryRequest(on library: LibraryGridRepoMock, expectedCount: Int) async {
        for _ in 0..<80 {
            if library.albumQueryFilters.count >= expectedCount {
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class LibraryGridRepoMock: LibraryRepoProtocol {
    struct PagedQuery: Equatable {
        let filter: AlbumQueryFilter
        let after: AlbumCursor?
        let limit: Int
    }

    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]
    var queryErrorByFilter: [AlbumQueryFilter: LibraryError] = [:]
    var albumQueryFilters: [AlbumQueryFilter] = []
    var pagedQueryCalls: [PagedQuery] = []
    var authenticatedArtworkURLByRawValue: [String: URL] = [:]
    var authenticatedArtworkURLRequests: [String?] = []
    var tracksByAlbumID: [String: [Track]] = [:]
    var refreshReasons: [LibraryRefreshReason] = []
    var refreshHook: (() -> Void)?
    var refreshError: LibraryError?

    func albums(page: LibraryPage) async throws -> [Album] {
        []
    }

    func album(id: String) async throws -> Album? {
        nil
    }

    func searchAlbums(query: String) async throws -> [Album] {
        let filter = AlbumQueryFilter(textQuery: query)
        albumQueryFilters.append(filter)
        if let error = queryErrorByFilter[filter] {
            throw error
        }
        return queriedAlbumsByFilter[filter] ?? []
    }

    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        albumQueryFilters.append(filter)
        if let error = queryErrorByFilter[filter] {
            throw error
        }
        return queriedAlbumsByFilter[filter] ?? []
    }

    func queryAlbums(filter: AlbumQueryFilter, after: AlbumCursor?, limit: Int) async throws -> [Album] {
        // Record into albumQueryFilters too so existing grid-load assertions still hold,
        // plus the richer paged tracker for pagination/re-entrancy assertions.
        albumQueryFilters.append(filter)
        pagedQueryCalls.append(PagedQuery(filter: filter, after: after, limit: limit))
        if let error = queryErrorByFilter[filter] {
            throw error
        }
        let sorted = (queriedAlbumsByFilter[filter] ?? []).sorted { lhs, rhs in
            (lhs.artistName, lhs.title, lhs.plexID) < (rhs.artistName, rhs.title, rhs.plexID)
        }
        let start: Int
        if let after {
            start = sorted.firstIndex {
                ($0.artistName, $0.title, $0.plexID) > (after.artistName, after.title, after.plexID)
            } ?? sorted.count
        } else {
            start = 0
        }
        return Array(sorted[start...].prefix(limit))
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        tracksByAlbumID[albumID] ?? []
    }

    func track(id: String) async throws -> Track? {
        nil
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        let album = queriedAlbumsByFilter.values.flatMap { $0 }.first { $0.plexID == albumID }
        return AlbumDetailRefreshOutcome(album: album, tracks: tracksByAlbumID[albumID] ?? [])
    }

    func collections() async throws -> [Collection] {
        []
    }

    func collection(id: String) async throws -> Collection? {
        nil
    }

    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }

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

    func artistAlbums(artistName: String) async throws -> [Album] { [] }

    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }

    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }

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
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
    func shuffleAllAlbums() async throws { }
}
