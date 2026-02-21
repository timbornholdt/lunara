import Foundation
import Observation

@MainActor
protocol ArtistsListActionRouting: AlbumDetailActionRouting, AnyObject {
    func playArtist(_ artist: Artist) async throws
    func shuffleArtist(_ artist: Artist) async throws
}

extension AppCoordinator: ArtistsListActionRouting { }

@MainActor
@Observable
final class ArtistsListViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    let actions: ArtistsListActionRouting
    private let downloadManager: DownloadManagerProtocol?

    var artists: [Artist] = []
    var searchQuery = "" {
        didSet {
            scheduleSearch()
        }
    }
    var queriedArtists: [Artist] = []
    var loadingState: LoadingState = .idle
    var artworkByArtistID: [String: URL] = [:]
    var errorBannerState = ErrorBannerState()

    private var pendingArtworkArtistIDs: Set<String> = []
    private var searchRequestID = 0
    private var searchTask: Task<Void, Never>?

    var sectionedArtists: [(letter: String, artists: [Artist])] {
        let source = isSearchActive ? queriedArtists : artists
        let grouped = Dictionary(grouping: source) { artist -> String in
            let sortName = artist.effectiveSortName
            guard let first = sortName.first else { return "#" }
            let upper = String(first).uppercased()
            return upper.rangeOfCharacter(from: .letters) != nil ? upper : "#"
        }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (letter: $0.key, artists: $0.value) }
    }

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: ArtistsListActionRouting,
        downloadManager: DownloadManagerProtocol? = nil
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await reloadArtists()
    }

    func refresh() async {
        do {
            _ = try await library.refreshLibrary(reason: .userInitiated)
            await reloadArtists()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    func makeArtistDetailViewModel(for artist: Artist) -> ArtistDetailViewModel {
        ArtistDetailViewModel(
            artist: artist,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
            downloadManager: downloadManager
        )
    }

    func thumbnailURL(for artistID: String) -> URL? {
        artworkByArtistID[artistID]
    }

    func loadThumbnailIfNeeded(for artist: Artist) {
        guard thumbnailURL(for: artist.plexID) == nil else {
            return
        }

        guard pendingArtworkArtistIDs.insert(artist.plexID).inserted else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: artist.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: artist.plexID,
                    ownerKind: .artist,
                    sourceURL: sourceURL
                ) {
                    self.artworkByArtistID[artist.plexID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking; leave placeholder visible when fetch fails.
            }

            self.pendingArtworkArtistIDs.remove(artist.plexID)
        }
    }

    private var isSearchActive: Bool {
        !normalizedSearchQuery(searchQuery).isEmpty
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let normalizedQuery = normalizedSearchQuery(searchQuery)
        guard !normalizedQuery.isEmpty else {
            queriedArtists = []
            return
        }

        searchRequestID += 1
        let requestID = searchRequestID
        searchTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let results = try await library.searchArtists(query: normalizedQuery)
                guard requestID == searchRequestID else {
                    return
                }
                queriedArtists = results
            } catch {
                guard requestID == searchRequestID else {
                    return
                }
                queriedArtists = []
                errorBannerState.show(message: userFacingMessage(for: error))
            }
        }
    }

    private func reloadArtists() async {
        loadingState = .loading
        do {
            let allArtists = try await library.artists()
            artists = allArtists.sorted {
                $0.effectiveSortName.localizedCaseInsensitiveCompare($1.effectiveSortName) == .orderedAscending
            }
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
