import Foundation
import Observation

@MainActor
@Observable
final class CollectionDetailViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let collection: Collection
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: CollectionsListActionRouting

    var albums: [Album] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkURL: URL?
    var artworkByAlbumID: [String: URL] = [:]

    private var pendingArtworkAlbumIDs: Set<String> = []

    init(
        collection: Collection,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: CollectionsListActionRouting
    ) {
        self.collection = collection
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        loadingState = .loading
        await loadAlbums()
        await loadCollectionArtwork()
    }

    func playAll() async {
        await runAction {
            try await actions.playCollection(collection)
        }
    }

    func shuffle() async {
        await runAction {
            try await actions.shuffleCollection(collection)
        }
    }

    func playAlbum(_ album: Album) async {
        await runAction {
            try await actions.playAlbum(album)
        }
    }

    func queueAlbumNext(_ album: Album) async {
        await runAction {
            try await actions.queueAlbumNext(album)
        }
    }

    func queueAlbumLater(_ album: Album) async {
        await runAction {
            try await actions.queueAlbumLater(album)
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

    func albumThumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadAlbumThumbnailIfNeeded(for album: Album) {
        guard albumThumbnailURL(for: album.plexID) == nil else {
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
                // Artwork is non-blocking; leave placeholder visible when fetch fails.
            }

            self.pendingArtworkAlbumIDs.remove(album.plexID)
        }
    }

    private func loadAlbums() async {
        do {
            albums = try await library.collectionAlbums(collectionID: collection.plexID)
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func loadCollectionArtwork() async {
        do {
            let sourceURL = try await library.authenticatedArtworkURL(for: collection.thumbURL)
            artworkURL = try await artworkPipeline.fetchFullSize(
                for: collection.plexID,
                ownerKind: .collection,
                sourceURL: sourceURL
            )
        } catch {
            // Artwork is non-blocking for detail presentation.
        }
    }

    private func runAction(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let lunaraError = error as? LunaraError {
            return lunaraError.userMessage
        }
        return error.localizedDescription
    }
}
