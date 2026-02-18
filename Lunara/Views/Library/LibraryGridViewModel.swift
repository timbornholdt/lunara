import Foundation
import Observation
import os

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
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "LibraryGridViewModel")

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
            logger.debug("Skipping initial load because state is not idle")
            return
        }

        logger.info("Loading initial album page with pageSize=\(self.pageSize, privacy: .public)")
        await loadFirstPage(clearExistingAlbums: false)
    }

    func refresh() async {
        logger.info("Refreshing albums from first page")
        await loadFirstPage(clearExistingAlbums: true)
    }

    func loadNextPageIfNeeded(currentAlbumID: String?) async {
        guard shouldLoadNextPage(currentAlbumID: currentAlbumID) else {
            return
        }

        await loadNextPage()
    }

    func playAlbum(_ album: Album) async {
        logger.info("Play tapped for album id=\(album.plexID, privacy: .public) title=\(album.title, privacy: .public)")
        do {
            try await actions.playAlbum(album)
        } catch let error as LunaraError {
            logger.error("Play request failed for album id=\(album.plexID, privacy: .public): \(error.userMessage, privacy: .public)")
            errorBannerState.show(message: error.userMessage)
        } catch {
            logger.error("Play request failed for album id=\(album.plexID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorBannerState.show(message: error.localizedDescription)
        }
    }

    func thumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadThumbnailIfNeeded(for album: Album) {
        guard thumbnailURL(for: album.plexID) == nil else {
            logger.debug("Skipping artwork load for album id=\(album.plexID, privacy: .public): cached thumbnail already present")
            return
        }

        guard pendingArtworkAlbumIDs.insert(album.plexID).inserted else {
            logger.debug("Skipping artwork load for album id=\(album.plexID, privacy: .public): request already in flight")
            return
        }

        let sourceURL = artworkSourceURL(from: album.thumbURL)
        logger.info(
            "Requesting artwork thumbnail for album id=\(album.plexID, privacy: .public) rawThumb=\(album.thumbURL ?? "nil", privacy: .public) sourceURL=\(sourceURL?.absoluteString ?? "nil", privacy: .public)"
        )

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                ) {
                    self.artworkByAlbumID[album.plexID] = resolvedURL
                    logger.info(
                        "Artwork resolved for album id=\(album.plexID, privacy: .public) localURL=\(resolvedURL.absoluteString, privacy: .public)"
                    )
                } else {
                    logger.debug("Artwork pipeline returned nil for album id=\(album.plexID, privacy: .public)")
                }
            } catch {
                // Artwork is non-blocking for this screen; leave placeholder visible when fetch fails.
                logger.error(
                    "Artwork load failed for album id=\(album.plexID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }

            self.pendingArtworkAlbumIDs.remove(album.plexID)
        }
    }

    private func loadFirstPage(clearExistingAlbums: Bool) async {
        logger.info("Loading first page clearExistingAlbums=\(clearExistingAlbums, privacy: .public)")
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
            logger.info(
                "Loaded first page albums=\(firstPageAlbums.count, privacy: .public) hasMorePages=\(self.hasMorePages, privacy: .public)"
            )
        } catch {
            logger.error("Failed loading first page: \(error.localizedDescription, privacy: .public)")
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func loadNextPage() async {
        guard hasMorePages else {
            logger.debug("Skipping next page load because hasMorePages is false")
            return
        }

        logger.info("Loading next page number=\(self.nextPageNumber, privacy: .public)")
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
            logger.info(
                "Loaded next page count=\(nextPageAlbums.count, privacy: .public) totalAlbums=\(self.albums.count, privacy: .public) hasMorePages=\(self.hasMorePages, privacy: .public)"
            )
        } catch {
            logger.error("Failed loading next page number=\(self.nextPageNumber, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

    private func artworkSourceURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              let sourceURL = URL(string: rawValue),
              sourceURL.scheme != nil else {
            if let rawValue {
                logger.debug("Artwork raw thumb is not an absolute URL and will be passed as nil sourceURL: \(rawValue, privacy: .public)")
            } else {
                logger.debug("Artwork raw thumb is nil; sourceURL will be nil")
            }
            return nil
        }

        return sourceURL
    }
}
