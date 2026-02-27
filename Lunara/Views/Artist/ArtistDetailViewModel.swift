import Foundation
import Observation

@MainActor
@Observable
final class ArtistDetailViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let artist: Artist
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: ArtistsListActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let gardenClient: GardenAPIClientProtocol?

    var albums: [Album] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkURL: URL?
    var artworkByAlbumID: [String: URL] = [:]

    private var pendingArtworkAlbumIDs: Set<String> = []

    init(
        artist: Artist,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: ArtistsListActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        gardenClient: GardenAPIClientProtocol? = nil
    ) {
        self.artist = artist
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.gardenClient = gardenClient
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        loadingState = .loading
        await loadAlbums()
        await loadArtistArtwork()
    }

    func playAll() async {
        await runAction {
            try await actions.playArtist(artist)
        }
    }

    func shuffle() async {
        await runAction {
            try await actions.shuffleArtist(artist)
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
            downloadManager: downloadManager,
            gardenClient: gardenClient,
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
            albums = try await library.artistAlbums(artistName: artist.name)
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func loadArtistArtwork() async {
        do {
            let sourceURL = try await library.authenticatedArtworkURL(for: artist.thumbURL)
            artworkURL = try await artworkPipeline.fetchFullSize(
                for: artist.plexID,
                ownerKind: .artist,
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
