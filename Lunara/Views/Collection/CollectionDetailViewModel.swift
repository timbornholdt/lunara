import Foundation
import Observation
import os

@MainActor
@Observable
final class CollectionDetailViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    enum CollectionSyncState: Equatable {
        case idle
        case syncing(currentAlbum: Int, totalAlbums: Int)
        case synced
        case failed(String)
    }

    let collection: Collection
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: CollectionsListActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let gardenClient: GardenAPIClientProtocol?
    private let offlineStore: OfflineStoreProtocol?
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "CollectionDetailViewModel")

    var albums: [Album] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkURL: URL?
    var artworkByAlbumID: [String: URL] = [:]
    var syncState: CollectionSyncState = .idle

    private var pendingArtworkAlbumIDs: Set<String> = []

    init(
        collection: Collection,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: CollectionsListActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        gardenClient: GardenAPIClientProtocol? = nil,
        offlineStore: OfflineStoreProtocol? = nil
    ) {
        self.collection = collection
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.gardenClient = gardenClient
        self.offlineStore = offlineStore
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        loadingState = .loading
        await loadAlbums()
        await loadCollectionArtwork()
        await refreshSyncState()
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

    func toggleSync() async {
        guard let downloadManager, let offlineStore else {
            logger.warning("toggleSync: no downloadManager or offlineStore")
            return
        }

        if case .synced = syncState {
            await stopSyncing()
            return
        }

        guard !albums.isEmpty else { return }

        let totalAlbums = albums.count
        for (index, album) in albums.enumerated() {
            syncState = .syncing(currentAlbum: index + 1, totalAlbums: totalAlbums)
            do {
                let tracks = try await library.tracks(forAlbum: album.plexID)
                guard !tracks.isEmpty else { continue }
                await downloadManager.downloadAlbum(album, tracks: tracks)
                let state = downloadManager.downloadState(forAlbum: album.plexID)
                if case .failed(let msg) = state {
                    let albumTitle = album.title
                    logger.warning("toggleSync: album '\(albumTitle, privacy: .public)' failed: \(msg, privacy: .public)")
                    syncState = .failed("Failed on \(album.title)")
                    return
                }
            } catch {
                syncState = .failed("Failed to load tracks for \(album.title)")
                return
            }
        }

        // Mark as synced after all downloads complete
        try? await offlineStore.addSyncedCollection(collection.plexID)
        syncState = .synced
    }

    func stopSyncing() async {
        guard let downloadManager else { return }
        await downloadManager.unsyncCollection(collection.plexID, library: library)
        syncState = .idle
    }

    func refreshSyncState() async {
        guard let offlineStore else { return }
        let isSynced = (try? await offlineStore.isSyncedCollection(collection.plexID)) ?? false
        if isSynced {
            syncState = .synced
        } else if case .syncing = syncState {
            // Don't override active syncing state
        } else {
            syncState = .idle
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
