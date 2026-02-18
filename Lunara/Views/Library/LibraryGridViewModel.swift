import Foundation
import Observation

@MainActor
protocol LibraryGridActionRouting: AnyObject {
    func playAlbum(_ album: Album) async throws
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

    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: LibraryGridActionRouting

    private let pageSize: Int
    private let prefetchThreshold: Int

    private var nextPageNumber = 1
    private var hasMorePages = true
    private var pendingArtworkAlbumIDs: Set<String> = []

    var albums: [Album] = []
    var loadingState: LoadingState = .idle
    var isLoadingNextPage = false
    var artworkByAlbumID: [String: URL] = [:]
    var errorBannerState = ErrorBannerState()

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: LibraryGridActionRouting,
        pageSize: Int = 40,
        prefetchThreshold: Int = 8
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.pageSize = max(1, pageSize)
        self.prefetchThreshold = max(1, prefetchThreshold)
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await loadFirstPage(clearExistingAlbums: false)
    }

    func refresh() async {
        await loadFirstPage(clearExistingAlbums: true)
    }

    func loadNextPageIfNeeded(currentAlbumID: String?) async {
        guard shouldLoadNextPage(currentAlbumID: currentAlbumID) else {
            return
        }

        await loadNextPage()
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

    private func loadFirstPage(clearExistingAlbums: Bool) async {
        if clearExistingAlbums {
            albums = []
            artworkByAlbumID = [:]
        }

        loadingState = .loading
        nextPageNumber = 1
        hasMorePages = true

        do {
            let firstPageAlbums = try await library.albums(page: LibraryPage(number: 1, size: pageSize))
            albums = firstPageAlbums
            hasMorePages = firstPageAlbums.count == pageSize
            nextPageNumber = hasMorePages ? 2 : 1
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func loadNextPage() async {
        guard hasMorePages else {
            return
        }

        isLoadingNextPage = true
        defer {
            isLoadingNextPage = false
        }

        do {
            let nextPageAlbums = try await library.albums(page: LibraryPage(number: nextPageNumber, size: pageSize))
            appendUniqueAlbums(nextPageAlbums)
            hasMorePages = nextPageAlbums.count == pageSize
            if hasMorePages {
                nextPageNumber += 1
            }
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    private func shouldLoadNextPage(currentAlbumID: String?) -> Bool {
        guard hasMorePages, !isLoadingNextPage else {
            return false
        }

        guard !albums.isEmpty else {
            return false
        }

        guard let currentAlbumID,
              let currentIndex = albums.firstIndex(where: { $0.plexID == currentAlbumID }) else {
            return true
        }

        let triggerIndex = max(albums.count - prefetchThreshold, 0)
        return currentIndex >= triggerIndex
    }

    private func appendUniqueAlbums(_ incomingAlbums: [Album]) {
        guard !incomingAlbums.isEmpty else {
            return
        }

        let existingIDs = Set(albums.map(\.plexID))
        let uniqueIncoming = incomingAlbums.filter { !existingIDs.contains($0.plexID) }
        albums.append(contentsOf: uniqueIncoming)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let lunaraError = error as? LunaraError {
            return lunaraError.userMessage
        }
        return error.localizedDescription
    }
}
