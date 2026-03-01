import Foundation
import Observation

@MainActor
protocol PlaylistsListActionRouting: AlbumDetailActionRouting, AnyObject {
    func playPlaylist(_ playlist: Playlist) async throws
    func shufflePlaylist(_ playlist: Playlist) async throws
}

extension AppCoordinator: PlaylistsListActionRouting { }

@MainActor
@Observable
final class PlaylistsListViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    let actions: PlaylistsListActionRouting
    private let gardenClient: GardenAPIClientProtocol?

    var playlists: [Playlist] = []
    var searchQuery = "" {
        didSet {
            scheduleSearch()
        }
    }
    var queriedPlaylists: [Playlist] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkByPlaylistID: [String: URL] = [:]

    private var pendingArtworkPlaylistIDs: Set<String> = []
    private var searchRequestID = 0
    private var searchTask: Task<Void, Never>?

    var pinnedPlaylists: [Playlist] {
        filteredPlaylists.filter(\.isPinnedPlaylist)
    }

    var unpinnedPlaylists: [Playlist] {
        filteredPlaylists.filter { !$0.isPinnedPlaylist }
    }

    private var filteredPlaylists: [Playlist] {
        guard isSearchActive else {
            return playlists
        }
        return queriedPlaylists
    }

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: PlaylistsListActionRouting,
        gardenClient: GardenAPIClientProtocol? = nil
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.gardenClient = gardenClient
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await reloadPlaylists()
    }

    func refresh() async {
        do {
            _ = try await library.refreshLibrary(reason: .userInitiated)
            await reloadPlaylists()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    func makePlaylistDetailViewModel(for playlist: Playlist) -> PlaylistDetailViewModel {
        PlaylistDetailViewModel(
            playlist: playlist,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
            gardenClient: gardenClient
        )
    }

    private var isSearchActive: Bool {
        !normalizedSearchQuery(searchQuery).isEmpty
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let normalizedQuery = normalizedSearchQuery(searchQuery)
        guard !normalizedQuery.isEmpty else {
            queriedPlaylists = []
            return
        }

        searchRequestID += 1
        let requestID = searchRequestID
        searchTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let results = try await library.searchPlaylists(query: normalizedQuery)
                guard requestID == searchRequestID else {
                    return
                }
                queriedPlaylists = results.map(Playlist.init(snapshot:))
            } catch {
                guard requestID == searchRequestID else {
                    return
                }
                queriedPlaylists = []
                errorBannerState.show(message: userFacingMessage(for: error))
            }
        }
    }

    func thumbnailURL(for playlistID: String) -> URL? {
        artworkByPlaylistID[playlistID]
    }

    func loadThumbnailIfNeeded(for playlist: Playlist) {
        guard thumbnailURL(for: playlist.plexID) == nil else {
            return
        }

        guard pendingArtworkPlaylistIDs.insert(playlist.plexID).inserted else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: playlist.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: playlist.plexID,
                    ownerKind: .playlist,
                    sourceURL: sourceURL
                ) {
                    self.artworkByPlaylistID[playlist.plexID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking
            }

            self.pendingArtworkPlaylistIDs.remove(playlist.plexID)
        }
    }

    private func reloadPlaylists() async {
        loadingState = .loading
        do {
            let snapshots = try await library.playlists()
            playlists = snapshots
                .map(Playlist.init(snapshot:))
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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

    private func userFacingMessage(for error: Error) -> String {
        if let lunaraError = error as? LunaraError {
            return lunaraError.userMessage
        }
        return error.localizedDescription
    }
}
