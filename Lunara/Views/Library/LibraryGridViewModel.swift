import Foundation
import Observation

@MainActor
protocol LibraryGridActionRouting: AlbumDetailActionRouting, AnyObject { }

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

    private var pendingArtworkAlbumIDs: Set<String> = []
    private var searchRequestID = 0
    private var searchTask: Task<Void, Never>?

    var albums: [Album] = []
    var searchQuery = "" {
        didSet {
            scheduleSearch()
        }
    }
    var queriedAlbums: [Album] = []
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
        actions: LibraryGridActionRouting
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await reloadCachedCatalog()
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

    func makeAlbumDetailViewModel(for album: Album) -> AlbumDetailViewModel {
        AlbumDetailViewModel(
            album: album,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
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
            albums = try await library.queryAlbums(filter: .all)
            await refreshSearchResultsIfNeeded()
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func normalizedSearchQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
