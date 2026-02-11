import Foundation
import Combine
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var sections: [PlexLibrarySection] = []
    @Published var selectedSection: PlexLibrarySection?
    @Published var albums: [PlexAlbum] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var hasLoadedSections = false

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private var selectionStore: PlexLibrarySelectionStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let snapshotStore: LibrarySnapshotStoring
    private let artworkPrefetcher: ArtworkPrefetching
    private let settingsStore: AppSettingsStoring
    private let logger: (String) -> Void
    private var albumGroups: [String: [PlexAlbum]] = [:]

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        selectionStore: PlexLibrarySelectionStoring = UserDefaultsLibrarySelectionStore(),
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
        artworkPrefetcher: ArtworkPrefetching = ArtworkLoader.shared,
        settingsStore: AppSettingsStoring = UserDefaultsAppSettingsStore(),
        logger: @escaping (String) -> Void = { print($0) },
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.selectionStore = selectionStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.snapshotStore = snapshotStore
        self.artworkPrefetcher = artworkPrefetcher
        self.settingsStore = settingsStore
        self.logger = logger
    }

    func loadSections() async {
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
            let fetched = try await service.fetchLibrarySections()
            sections = fetched.filter { $0.type == "artist" || $0.type == "music" }
            selectedSection = sections.first
            if let selectedSection {
                selectionStore.selectedSectionKey = selectedSection.key
            } else {
                errorMessage = "No music library found."
                return
            }
            if let selected = selectedSection {
                try await loadAlbums(section: selected)
                saveSnapshot(albums: albums)
                prefetchArtwork(for: albums)
            }
            hasLoadedSections = true
        } catch {
            print("LibraryViewModel.loadSections error: \(error)")
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                if let statusCode = (error as? PlexHTTPError)?.statusCode {
                    errorMessage = "Failed to load libraries (HTTP \(statusCode))."
                } else {
                    errorMessage = "Failed to load libraries."
                }
            }
        }
    }

    func loadSectionsIfNeeded() async {
        guard hasLoadedSections == false else { return }
        await loadSections()
    }

    func selectSection(_ section: PlexLibrarySection) async {
        selectedSection = section
        selectionStore.selectedSectionKey = section.key
        do {
            try await loadAlbums(section: section)
            saveSnapshot(albums: albums)
            prefetchArtwork(for: albums)
        } catch {
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                if let statusCode = (error as? PlexHTTPError)?.statusCode {
                    errorMessage = "Failed to load albums (HTTP \(statusCode))."
                } else {
                    errorMessage = "Failed to load albums."
                }
            }
        }
    }

    private func loadAlbums(section: PlexLibrarySection) async throws {
        guard let serverURL = serverStore.serverURL else { return }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return }
        let service = libraryServiceFactory(serverURL, token)
        let fetchedAlbums = try await service.fetchAlbums(sectionId: section.key)
        albumGroups = Dictionary(grouping: fetchedAlbums, by: albumDedupKey(for:))
        let dedupedAlbums = dedupeAlbums(fetchedAlbums)
        if settingsStore.isAlbumDedupDebugEnabled {
            logAlbumDedupDebug(albums: fetchedAlbums)
        }
        albums = dedupedAlbums
    }

    func ratingKeys(for album: PlexAlbum) -> [String] {
        let key = albumDedupKey(for: album)
        let keys = albumGroups[key]?.map(\.ratingKey) ?? [album.ratingKey]
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func logAlbumDedupDebug(albums: [PlexAlbum]) {
        let grouped = Dictionary(grouping: albums) { album in
            let title = album.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let year = album.year.map(String.init) ?? ""
            return "\(title)|\(artist)|\(year)"
        }

        let duplicates = grouped.filter { $0.value.count > 1 }
        guard !duplicates.isEmpty else { return }

        logger("----- Album De-dup Debug (duplicates: \(duplicates.count)) -----")
        for (key, items) in duplicates {
            logger("Duplicate group: \(key) (count: \(items.count))")
            for album in items {
                logger("""
                - ratingKey: \(album.ratingKey)
                  title: \(album.title)
                  artist: \(album.artist ?? "nil")
                  year: \(album.year.map(String.init) ?? "nil")
                  titleSort: \(album.titleSort ?? "nil")
                  originalTitle: \(album.originalTitle ?? "nil")
                  editionTitle: \(album.editionTitle ?? "nil")
                  guid: \(album.guid ?? "nil")
                  librarySectionID: \(album.librarySectionID.map(String.init) ?? "nil")
                  parentRatingKey: \(album.parentRatingKey ?? "nil")
                  studio: \(album.studio ?? "nil")
                  thumb: \(album.thumb ?? "nil")
                  art: \(album.art ?? "nil")
                  key: \(album.key ?? "nil")
                """)
            }
        }
        logger("----- End Album De-dup Debug -----")
    }

    private func dedupeAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        var seen: [String: Int] = [:]
        var result: [PlexAlbum] = []
        result.reserveCapacity(albums.count)

        for album in albums {
            let identity = albumDedupKey(for: album)
            if let existingIndex = seen[identity] {
                if shouldReplace(existing: result[existingIndex], candidate: album) {
                    result[existingIndex] = album
                }
            } else {
                seen[identity] = result.count
                result.append(album)
            }
        }

        return result
    }

    private func albumDedupKey(for album: PlexAlbum) -> String {
        if let guid = album.guid, !guid.isEmpty {
            return guid
        }
        let title = album.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let year = album.year.map(String.init) ?? ""
        return "\(title)|\(artist)|\(year)"
    }

    private func shouldReplace(existing: PlexAlbum, candidate: PlexAlbum) -> Bool {
        let existingScore = artworkScore(for: existing)
        let candidateScore = artworkScore(for: candidate)
        if candidateScore != existingScore {
            return candidateScore > existingScore
        }
        return false
    }

    private func artworkScore(for album: PlexAlbum) -> Int {
        var score = 0
        if album.art != nil { score += 2 }
        if album.thumb != nil { score += 1 }
        return score
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadSnapshotIfAvailable() -> Bool {
        guard let snapshot = try? snapshotStore.load() else { return false }
        let snapshotAlbums = snapshot.albums.map { $0.toPlexAlbum() }
        guard !snapshotAlbums.isEmpty else { return false }
        albums = snapshotAlbums
        return true
    }

    private func saveSnapshot(albums: [PlexAlbum]) {
        let existing = (try? snapshotStore.load()) ?? LibrarySnapshot(albums: [], collections: [])
        let snapshot = LibrarySnapshot(
            albums: albums.map { LibrarySnapshot.Album(album: $0) },
            collections: existing.collections,
            artists: existing.artists,
            musicSectionKey: existing.musicSectionKey
        )
        try? snapshotStore.save(snapshot)
    }

    private func prefetchArtwork(for albums: [PlexAlbum]) {
        guard let baseURL = serverStore.serverURL else { return }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return }
        let builder = ArtworkRequestBuilder(baseURL: baseURL, token: token)
        let requests = albums.prefix(24).compactMap { builder.albumRequest(for: $0, size: .grid) }
        artworkPrefetcher.prefetch(requests)
    }
}
