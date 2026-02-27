import Foundation
import Observation

@MainActor
protocol CollectionsListActionRouting: AlbumDetailActionRouting, AnyObject {
    func playCollection(_ collection: Collection) async throws
    func shuffleCollection(_ collection: Collection) async throws
}

extension AppCoordinator: CollectionsListActionRouting { }

@MainActor
@Observable
final class CollectionsListViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    let actions: CollectionsListActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let gardenClient: GardenAPIClientProtocol?
    private let offlineStore: OfflineStoreProtocol?

    var collections: [Collection] = []
    var searchQuery = "" {
        didSet {
            scheduleSearch()
        }
    }
    var queriedCollections: [Collection] = []
    var loadingState: LoadingState = .idle
    var artworkByCollectionID: [String: URL] = [:]
    var errorBannerState = ErrorBannerState()

    private var pendingArtworkCollectionIDs: Set<String> = []
    private var searchRequestID = 0
    private var searchTask: Task<Void, Never>?

    var pinnedCollections: [Collection] {
        filteredCollections.filter(\.isPinnedCollection)
    }

    var unpinnedCollections: [Collection] {
        filteredCollections.filter { !$0.isPinnedCollection }
    }

    private var filteredCollections: [Collection] {
        guard isSearchActive else {
            return collections
        }
        return queriedCollections
    }

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: CollectionsListActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        gardenClient: GardenAPIClientProtocol? = nil,
        offlineStore: OfflineStoreProtocol? = nil
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.gardenClient = gardenClient
        self.offlineStore = offlineStore
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await reloadCollections()
    }

    func refresh() async {
        do {
            _ = try await library.refreshLibrary(reason: .userInitiated)
            await reloadCollections()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    func makeCollectionDetailViewModel(for collection: Collection) -> CollectionDetailViewModel {
        CollectionDetailViewModel(
            collection: collection,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
            downloadManager: downloadManager,
            gardenClient: gardenClient,
            offlineStore: offlineStore
        )
    }

    func thumbnailURL(for collectionID: String) -> URL? {
        artworkByCollectionID[collectionID]
    }

    func loadThumbnailIfNeeded(for collection: Collection) {
        guard thumbnailURL(for: collection.plexID) == nil else {
            return
        }

        guard pendingArtworkCollectionIDs.insert(collection.plexID).inserted else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: collection.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: collection.plexID,
                    ownerKind: .collection,
                    sourceURL: sourceURL
                ) {
                    self.artworkByCollectionID[collection.plexID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking; leave placeholder visible when fetch fails.
            }

            self.pendingArtworkCollectionIDs.remove(collection.plexID)
        }
    }

    private var isSearchActive: Bool {
        !normalizedSearchQuery(searchQuery).isEmpty
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let normalizedQuery = normalizedSearchQuery(searchQuery)
        guard !normalizedQuery.isEmpty else {
            queriedCollections = []
            return
        }

        searchRequestID += 1
        let requestID = searchRequestID
        searchTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let results = try await library.searchCollections(query: normalizedQuery)
                guard requestID == searchRequestID else {
                    return
                }
                queriedCollections = results
            } catch {
                guard requestID == searchRequestID else {
                    return
                }
                queriedCollections = []
                errorBannerState.show(message: userFacingMessage(for: error))
            }
        }
    }

    private func reloadCollections() async {
        loadingState = .loading
        do {
            let allCollections = try await library.collections()
            collections = allCollections.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
