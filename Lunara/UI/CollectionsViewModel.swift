import Foundation
import Combine
import SwiftUI

@MainActor
final class CollectionsViewModel: ObservableObject {
    @Published var collections: [PlexCollection] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var hasLoadedCollections = false

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let logger: ([String]) -> Void
    private let snapshotStore: LibrarySnapshotStoring
    private let artworkPrefetcher: ArtworkPrefetching

    private(set) var sectionKey: String?

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        libraryServiceFactory: @escaping PlexLibraryServiceFactory = { serverURL, token in
            let config = PlexDefaults.configuration()
            let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
            return PlexLibraryService(
                httpClient: PlexHTTPClient(),
                requestBuilder: builder,
                paginator: PlexPaginator(pageSize: 50)
            )
        },
        sessionInvalidationHandler: @escaping () -> Void = {},
        logger: @escaping ([String]) -> Void = { titles in
            print("----- Collection Titles -----")
            titles.forEach { print("- \($0)") }
            print("----- End Collection Titles -----")
        },
        snapshotStore: LibrarySnapshotStoring = LibrarySnapshotStore(),
        artworkPrefetcher: ArtworkPrefetching = ArtworkLoader.shared
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.logger = logger
        self.snapshotStore = snapshotStore
        self.artworkPrefetcher = artworkPrefetcher
    }

    func loadCollections() async {
        errorMessage = nil
        let hadSnapshot = loadSnapshotIfAvailable()
        guard let serverURL = serverStore.serverURL else {
            errorMessage = "Missing server URL."
            return
        }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else {
            errorMessage = "Missing auth token."
            return
        }

        if hadSnapshot {
            isRefreshing = true
        } else {
            isLoading = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let service = libraryServiceFactory(serverURL, token)
            let sections = try await service.fetchLibrarySections()
            let musicSections = sections.filter { $0.type == "artist" || $0.type == "music" }
            guard let firstMusic = musicSections.first else {
                errorMessage = "No music library found."
                collections = []
                sectionKey = nil
                return
            }
            sectionKey = firstMusic.key

            let fetchedCollections = try await service.fetchCollections(sectionId: firstMusic.key)
            logger(fetchedCollections.map(\.title))
            collections = sortCollections(fetchedCollections)
            saveSnapshot(collections: collections)
            prefetchArtwork(for: collections)
            hasLoadedCollections = true
        } catch {
            print("CollectionsViewModel.loadCollections error: \(error)")
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                if let statusCode = (error as? PlexHTTPError)?.statusCode {
                    errorMessage = "Failed to load collections (HTTP \(statusCode))."
                } else {
                    errorMessage = "Failed to load collections."
                }
            }
        }
    }

    func loadCollectionsIfNeeded() async {
        guard hasLoadedCollections == false else { return }
        await loadCollections()
    }

    func isPinned(_ collection: PlexCollection) -> Bool {
        pinnedTitles.contains(collection.title)
    }

    private var pinnedTitles: [String] {
        ["Current Vibes", "The Key Albums"]
    }

    private func sortCollections(_ collections: [PlexCollection]) -> [PlexCollection] {
        let pinned = pinnedTitles.compactMap { title in
            collections.first(where: { $0.title == title })
        }
        let remaining = collections
            .filter { !pinnedTitles.contains($0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return pinned + remaining
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadSnapshotIfAvailable() -> Bool {
        guard let snapshot = try? snapshotStore.load() else { return false }
        let snapshotCollections = snapshot.collections.map { $0.toPlexCollection() }
        guard !snapshotCollections.isEmpty else { return false }
        collections = sortCollections(snapshotCollections)
        sectionKey = snapshot.musicSectionKey
        return true
    }

    private func saveSnapshot(collections: [PlexCollection]) {
        let existing = (try? snapshotStore.load()) ?? LibrarySnapshot(albums: [], collections: [])
        let snapshot = LibrarySnapshot(
            albums: existing.albums,
            collections: collections.map { LibrarySnapshot.Collection(collection: $0) },
            artists: existing.artists,
            musicSectionKey: sectionKey
        )
        try? snapshotStore.save(snapshot)
    }

    private func prefetchArtwork(for collections: [PlexCollection]) {
        guard let baseURL = serverStore.serverURL else { return }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return }
        let builder = ArtworkRequestBuilder(baseURL: baseURL, token: token)
        let requests = collections.prefix(24).compactMap { builder.collectionRequest(for: $0, size: .grid) }
        artworkPrefetcher.prefetch(requests)
    }
}
