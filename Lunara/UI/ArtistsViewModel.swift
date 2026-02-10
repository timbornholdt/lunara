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
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.snapshotStore = snapshotStore
        self.sessionInvalidationHandler = sessionInvalidationHandler
    }

    func loadArtists() async {
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
                artists = []
                return
            }

            let fetchedArtists = try await service.fetchArtists(sectionId: firstMusic.key)
            artists = sortArtists(fetchedArtists)
            saveSnapshot(artists: artists)
            hasLoadedArtists = true
        } catch {
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
