import Foundation
import Observation
import os

@MainActor
@Observable
final class PlaylistDetailViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let playlist: Playlist
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: PlaylistsListActionRouting
    private let gardenClient: GardenAPIClientProtocol?
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "PlaylistDetailViewModel")

    var tracks: [Track] = []
    var playlistItems: [LibraryPlaylistItemSnapshot] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkByAlbumID: [String: URL] = [:]
    var playlistArtworkURL: URL?
    var showGardenSheet = false
    var gardenSheetTrack: Track?
    var gardenSheetPlaylistItemID: String?

    private var pendingArtworkAlbumIDs: Set<String> = []

    var isChoppingBlock: Bool {
        playlist.title == "Chopping Block"
    }

    init(
        playlist: Playlist,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: PlaylistsListActionRouting,
        gardenClient: GardenAPIClientProtocol? = nil
    ) {
        self.playlist = playlist
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.gardenClient = gardenClient
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        loadingState = .loading
        loadPlaylistArtwork()
        await loadTracks()
    }

    func playAll() async {
        await runAction {
            guard !tracks.isEmpty else { return }
            try await actions.playTracksNow(tracks)
        }
    }

    func shuffle() async {
        await runAction {
            guard !tracks.isEmpty else { return }
            try await actions.playTracksNow(tracks.shuffled())
        }
    }

    func playFromTrack(_ track: Track) async {
        await runAction {
            if let index = tracks.firstIndex(where: { $0.plexID == track.plexID }) {
                let tracksFromHere = Array(tracks[index...])
                try await actions.playTracksNow(tracksFromHere)
            } else {
                try await actions.playTrackNow(track)
            }
        }
    }

    func queueTrackNext(_ track: Track) async {
        await runAction {
            try await actions.queueTrackNext(track)
        }
    }

    func queueTrackLater(_ track: Track) async {
        await runAction {
            try await actions.queueTrackLater(track)
        }
    }

    /// Keep: silently remove from Chopping Block playlist
    func keepItem(at index: Int) async {
        guard index < playlistItems.count else { return }
        let item = playlistItems[index]
        guard let playlistItemID = item.playlistItemID else {
            errorBannerState.show(message: "Cannot remove item: missing playlist item ID")
            return
        }

        do {
            try await library.removeFromPlaylist(playlistID: playlist.plexID, playlistItemID: playlistItemID)
            playlistItems.remove(at: index)
            if index < tracks.count {
                tracks.remove(at: index)
            }
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    /// Remove with garden todo: show sheet, then remove from playlist on submit
    func removeWithTodo(at index: Int) {
        guard index < playlistItems.count, index < tracks.count else { return }
        let item = playlistItems[index]
        gardenSheetTrack = tracks[index]
        gardenSheetPlaylistItemID = item.playlistItemID
        showGardenSheet = true
    }

    func submitGardenTodo(body: String) async throws {
        guard let track = gardenSheetTrack,
              let gardenClient else {
            return
        }

        let album = try await library.album(id: track.albumID)
        let albumName = album?.title ?? "Unknown Album"
        try await gardenClient.submitTodo(
            artistName: track.artistName,
            albumName: albumName,
            plexID: track.plexID,
            body: body
        )

        // Remove from playlist after successful todo submission
        if let playlistItemID = gardenSheetPlaylistItemID {
            try await library.removeFromPlaylist(playlistID: playlist.plexID, playlistItemID: playlistItemID)
            if let index = playlistItems.firstIndex(where: { $0.playlistItemID == playlistItemID }) {
                playlistItems.remove(at: index)
                if index < tracks.count {
                    tracks.remove(at: index)
                }
            }
        }
    }

    func albumThumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadAlbumThumbnailIfNeeded(for track: Track) {
        guard albumThumbnailURL(for: track.albumID) == nil else {
            return
        }

        guard pendingArtworkAlbumIDs.insert(track.albumID).inserted else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: track.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: track.albumID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                ) {
                    self.artworkByAlbumID[track.albumID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking
            }

            self.pendingArtworkAlbumIDs.remove(track.albumID)
        }
    }

    private func loadPlaylistArtwork() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: playlist.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: playlist.plexID,
                    ownerKind: .playlist,
                    sourceURL: sourceURL
                ) {
                    self.playlistArtworkURL = resolvedURL
                }
            } catch {
                // Artwork is non-blocking
            }
        }
    }

    private func loadTracks() async {
        do {
            let items = try await library.playlistItems(playlistID: playlist.plexID)
            playlistItems = items

            var resolvedTracks: [Track] = []
            resolvedTracks.reserveCapacity(items.count)

            for item in items {
                if let track = try await library.track(id: item.trackID) {
                    resolvedTracks.append(track)
                } else {
                    logger.warning("Playlist item trackID '\(item.trackID, privacy: .public)' not found in library")
                    // Insert a placeholder-less entry - skip to keep arrays aligned
                    // Remove the playlist item to keep arrays in sync
                    playlistItems.removeAll { $0.trackID == item.trackID && $0.position == item.position }
                }
            }

            tracks = resolvedTracks
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
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
