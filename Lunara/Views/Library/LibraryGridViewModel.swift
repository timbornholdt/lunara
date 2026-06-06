import Foundation
import Observation

@MainActor
protocol LibraryGridActionRouting: AlbumDetailActionRouting, AnyObject {
    func shuffleAllAlbums() async throws
}

extension AppCoordinator: LibraryGridActionRouting { }

@MainActor
@Observable
final class LibraryGridViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: LibraryGridActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let gardenClient: GardenAPIClientProtocol?

    private var pendingArtworkAlbumIDs: Set<String> = []
    private var searchRequestID = 0
    private var searchTask: Task<Void, Never>?

    // Keyset pagination state.
    private let pageSize = 50
    private var nextCursor: AlbumCursor?
    private var isLoadingNextPage = false
    // plexID of the album ~10 from the end of `albums`; the card whose appearance
    // triggers the next page load (O(1) compare, no array scan per card).
    private var triggerAlbumID: String?
    // Bumped on every full catalog replace; an in-flight append checks it after its
    // await so a background refresh mid-fetch can't append onto a replaced catalog.
    private var catalogGeneration = 0

    var albums: [Album] = []
    var searchQuery = "" {
        didSet {
            scheduleSearch()
        }
    }
    var queriedAlbums: [Album] = []
    var hasMorePages = true
    var loadingState: LoadingState = .idle
    var artworkByAlbumID: [String: URL] = [:]
    var errorBannerState = ErrorBannerState()

    var filteredAlbums: [Album] {
        guard isSearchActive else {
            return albums
        }

        return queriedAlbums
    }

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: LibraryGridActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        gardenClient: GardenAPIClientProtocol? = nil
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.gardenClient = gardenClient
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await reloadCachedCatalog()
    }

    /// Called as each grid card appears. Loads the next page only when the card
    /// that sits ~10 from the end scrolls into view.
    func loadNextPageIfNeeded(currentItem: Album) async {
        guard currentItem.plexID == triggerAlbumID else {
            return
        }
        await appendNextPage()
    }

    func refresh() async {
        do {
            _ = try await library.refreshLibrary(reason: .userInitiated)
            await reloadCachedCatalog()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    func playAlbum(_ album: Album) async {
        do {
            try await actions.playAlbum(album)
        } catch let error as LunaraError {
            errorBannerState.show(message: error.userMessage)
        } catch {
            errorBannerState.show(message: error.localizedDescription)
        }
    }

    func shuffleAll() async {
        do {
            try await actions.shuffleAllAlbums()
        } catch let error as LunaraError {
            errorBannerState.show(message: error.userMessage)
        } catch {
            errorBannerState.show(message: error.localizedDescription)
        }
    }

    func makeAlbumDetailViewModel(for album: Album) -> AlbumDetailViewModel {
        AlbumDetailViewModel(
            album: album,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
            downloadManager: downloadManager,
            gardenClient: gardenClient,
            review: album.review,
            genres: album.genres.isEmpty ? nil : album.genres,
            styles: album.styles,
            moods: album.moods
        )
    }

    func thumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadThumbnailIfNeeded(for album: Album) {
        guard thumbnailURL(for: album.plexID) == nil else {
            return
        }

        guard pendingArtworkAlbumIDs.insert(album.plexID).inserted else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: album.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                ) {
                    self.artworkByAlbumID[album.plexID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking for this screen; leave placeholder visible when fetch fails.
            }

            self.pendingArtworkAlbumIDs.remove(album.plexID)
        }
    }

    func userFacingMessage(for error: Error) -> String {
        if let lunaraError = error as? LunaraError {
            return lunaraError.userMessage
        }
        return error.localizedDescription
    }

    private var isSearchActive: Bool {
        !normalizedSearchQuery(searchQuery).isEmpty
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let normalizedQuery = normalizedSearchQuery(searchQuery)
        guard !normalizedQuery.isEmpty else {
            queriedAlbums = []
            return
        }

        searchRequestID += 1
        let requestID = searchRequestID
        searchTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.queryFilteredAlbumsInCatalog(
                filter: AlbumQueryFilter(textQuery: normalizedQuery),
                requestID: requestID
            )
        }
    }

    func refreshSearchResultsIfNeeded() async {
        guard isSearchActive else {
            return
        }

        searchTask?.cancel()
        searchRequestID += 1
        await queryFilteredAlbumsInCatalog(
            filter: AlbumQueryFilter(textQuery: normalizedSearchQuery(searchQuery)),
            requestID: searchRequestID
        )
    }

    private func queryFilteredAlbumsInCatalog(filter: AlbumQueryFilter, requestID: Int) async {
        do {
            let results = try await library.queryAlbums(filter: filter)
            guard requestID == searchRequestID else {
                return
            }
            queriedAlbums = results
        } catch {
            guard requestID == searchRequestID else {
                return
            }
            queriedAlbums = []
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    private func reloadCachedCatalog() async {
        loadingState = .loading
        do {
            try await replaceCatalog(limit: pageSize)
            await refreshSearchResultsIfNeeded()
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    /// Loads the first `limit` albums fresh and resets all pagination state. Used by
    /// initial load, pull-to-refresh, and background refresh — the single place a
    /// catalog replacement happens, so cursor/flags can never drift between them.
    func replaceCatalog(limit: Int) async throws {
        catalogGeneration += 1
        let generation = catalogGeneration
        let page = try await library.queryAlbums(filter: .all, after: nil, limit: limit)
        guard generation == catalogGeneration else {
            return // a newer replace superseded this one
        }
        isLoadingNextPage = false
        albums = page
        finishPage(page, limit: limit)
    }

    /// Depth-preserving limit for a background/refresh reload: at least one page,
    /// but enough to keep what the user has already scrolled through.
    var reloadLimit: Int {
        max(pageSize, albums.count)
    }

    private func appendNextPage() async {
        guard !isSearchActive,
              hasMorePages,
              !isLoadingNextPage,
              loadingState == .loaded,
              let cursor = nextCursor else {
            return
        }

        // Set synchronously before the first await so two near-simultaneous card
        // triggers can't both pass the guard and double-fetch / skip a page.
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        let generation = catalogGeneration
        do {
            let page = try await library.queryAlbums(filter: .all, after: cursor, limit: pageSize)
            guard generation == catalogGeneration else {
                return // a catalog replace happened during the fetch; drop this page
            }
            albums.append(contentsOf: page)
            finishPage(page, limit: pageSize)
        } catch {
            // Leave state intact; the next card appearance retries.
        }
    }

    /// Single place that records the cursor, whether more pages remain, and the
    /// next scroll trigger after a page is loaded.
    private func finishPage(_ page: [Album], limit: Int) {
        nextCursor = page.last.map(AlbumCursor.init(album:))
        hasMorePages = (page.count == limit)
        let triggerIndex = max(0, albums.count - 10)
        triggerAlbumID = albums.indices.contains(triggerIndex) ? albums[triggerIndex].plexID : nil
    }

    private func normalizedSearchQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
