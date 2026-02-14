import Foundation
import Combine
import SwiftUI

@MainActor
final class ArtistsViewModel: ObservableObject {
    @Published var artists: [PlexArtist] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var hasLoadedArtists = false

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let snapshotStore: LibrarySnapshotStoring
    private let cacheStore: LibraryCacheStoring

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
        snapshotStore: LibrarySnapshotStoring = LibrarySnapshotStore(),
        cacheStore: LibraryCacheStoring = LibraryCacheStore(),
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.snapshotStore = snapshotStore
        self.cacheStore = cacheStore
        self.sessionInvalidationHandler = sessionInvalidationHandler
    }

    func loadArtists() async {
        errorMessage = nil
        if let cached = cacheStore.load(key: .artists, as: [PlexArtist].self), !cached.isEmpty {
            artists = sortArtists(cached)
            hasLoadedArtists = true
            return
        }
        let hadSnapshot = loadSnapshotIfAvailable()
        if hadSnapshot {
            hasLoadedArtists = true
            return
        }
        await refresh()
    }

    func refresh() async {
        errorMessage = nil
        guard let serverURL = serverStore.serverURL else {
            errorMessage = "Missing server URL."
            return
        }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else {
            errorMessage = "Missing auth token."
            return
        }

        if artists.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
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
                artists = []
                return
            }

            let fetchedArtists = try await service.fetchArtists(sectionId: firstMusic.key)
            artists = sortArtists(fetchedArtists)
            cacheStore.save(key: .artists, value: fetchedArtists)
            saveSnapshot(artists: artists)
            hasLoadedArtists = true
        } catch {
            guard !Task.isCancelled else { return }
            print("ArtistsViewModel.loadArtists error: \(error)")
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                if let statusCode = (error as? PlexHTTPError)?.statusCode {
                    errorMessage = "Failed to load artists (HTTP \(statusCode))."
                } else {
                    errorMessage = "Failed to load artists."
                }
            }
        }
    }

    func loadArtistsIfNeeded() async {
        guard hasLoadedArtists == false else { return }
        await loadArtists()
    }

    func filteredArtists(query: String) -> [PlexArtist] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return artists }
        return artists.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func sortArtists(_ artists: [PlexArtist]) -> [PlexArtist] {
        artists.sorted { lhs, rhs in
            let leftKey = sortKey(for: lhs)
            let rightKey = sortKey(for: rhs)
            return leftKey.localizedCaseInsensitiveCompare(rightKey) == .orderedAscending
        }
    }

    private func sortKey(for artist: PlexArtist) -> String {
        let sort = artist.titleSort?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sort, !sort.isEmpty {
            return sort
        }
        return artist.title
    }

    private func loadSnapshotIfAvailable() -> Bool {
        guard let snapshot = try? snapshotStore.load() else { return false }
        let snapshotArtists = snapshot.artists.map { $0.toPlexArtist() }
        guard !snapshotArtists.isEmpty else { return false }
        artists = snapshotArtists
        return true
    }

    private func saveSnapshot(artists: [PlexArtist]) {
        let existing = (try? snapshotStore.load()) ?? LibrarySnapshot(albums: [], collections: [])
        let snapshot = LibrarySnapshot(
            albums: existing.albums,
            collections: existing.collections,
            artists: artists.map { LibrarySnapshot.Artist(artist: $0) },
            musicSectionKey: existing.musicSectionKey
        )
        try? snapshotStore.save(snapshot)
    }
}
