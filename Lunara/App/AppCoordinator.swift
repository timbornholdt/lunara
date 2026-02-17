import Foundation
import os
import SwiftUI

/// Coordinates app-wide dependencies and state
/// This is a minimal coordinator for Phase 1 - will expand in later phases
@MainActor
@Observable
final class AppCoordinator {

    // MARK: - Dependencies

    let authManager: AuthManager
    let plexClient: PlexAPIClient
    let libraryRepo: LibraryRepoProtocol
    let playbackEngine: PlaybackEngineProtocol
    let queueManager: QueueManagerProtocol
    let appRouter: AppRouter

    // MARK: - State

    var isSignedIn: Bool {
        authManager.isSignedIn
    }

    // MARK: - Initialization

    init(
        authManager: AuthManager,
        plexClient: PlexAPIClient,
        libraryRepo: LibraryRepoProtocol,
        playbackEngine: PlaybackEngineProtocol,
        queueManager: QueueManagerProtocol,
        appRouter: AppRouter
    ) {
        self.authManager = authManager
        self.plexClient = plexClient
        self.libraryRepo = libraryRepo
        self.playbackEngine = playbackEngine
        self.queueManager = queueManager
        self.appRouter = appRouter
    }

    convenience init() {
        // Initialize dependencies
        let keychain = KeychainHelper()
        let serverURL = Self.loadServerURL()

        // To resolve circular dependency:
        // 1. Create AuthManager without authAPI
        // 2. Create PlexAPIClient with that AuthManager
        // 3. AuthManager's authAPI can be set later if needed,
        //    or we use PlexAPIClient directly for OAuth

        // Create AuthManager (authAPI is optional, defaults to nil)
        let authManager = AuthManager(keychain: keychain)

        // Create PlexAPIClient (which implements PlexAuthAPIProtocol)
        let plexClient = PlexAPIClient(
            baseURL: serverURL,
            authManager: authManager,
            session: URLSession.shared
        )

        let libraryStore: LibraryStoreProtocol
        do {
            libraryStore = try Self.makeLibraryStore()
        } catch {
            fatalError("Failed to initialize LibraryStore: \(error)")
        }

        let libraryRepo = LibraryRepo(remote: plexClient, store: libraryStore)
        let playbackEngine = AVQueuePlayerEngine(audioSession: AudioSession())
        let queueManager = QueueManager(engine: playbackEngine)
        let appRouter = AppRouter(library: libraryRepo, queue: queueManager)

        self.init(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: libraryRepo,
            playbackEngine: playbackEngine,
            queueManager: queueManager,
            appRouter: appRouter
        )
    }

    // MARK: - Actions

    func fetchAlbums() async throws -> [Album] {
        let cachedAlbums = try await libraryRepo.fetchAlbums()

        do {
            _ = try await libraryRepo.refreshLibrary(reason: .userInitiated)
            return try await libraryRepo.fetchAlbums()
        } catch {
            if !cachedAlbums.isEmpty {
                return cachedAlbums
            }
            throw error
        }
    }

    func playAlbum(_ album: Album) async throws {
        try await appRouter.playAlbum(album)
    }

    func pausePlayback() {
        appRouter.pausePlayback()
    }

    func resumePlayback() {
        appRouter.resumePlayback()
    }

    func skipToNextTrack() {
        appRouter.skipToNextTrack()
    }

    func stopPlayback() {
        appRouter.stopPlayback()
    }

    /// Sign out and clear stored token
    func signOut() {
        do {
            try authManager.clearToken()
        } catch {
            assertionFailure("Failed to clear token during sign-out: \(error)")
        }
    }

    // MARK: - Private Helpers

    private static func loadServerURL() -> URL {
        // Try LocalConfig.plist first
        if let configPath = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath) as? [String: Any],
           let urlString = config["PLEX_SERVER_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // Default fallback (will fail, but better than crashing)
        return URL(string: "http://localhost:32400")!
    }

    private static func makeLibraryStore() throws -> LibraryStore {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LibraryError.operationFailed(reason: "Unable to resolve application support directory.")
        }

        let appDirectory = appSupportURL.appendingPathComponent("Lunara", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        let databaseURL = appDirectory.appendingPathComponent("library.sqlite")
        return try LibraryStore(databaseURL: databaseURL)
    }
}

struct AlbumDuplicateDebugReporter {
    func logReport(
        albums: [Album],
        logger: Logger,
        spotlightTitle: String? = nil,
        spotlightArtist: String? = nil
    ) {
        let report = makeReport(
            albums: albums,
            spotlightTitle: spotlightTitle,
            spotlightArtist: spotlightArtist
        )

        print(report)
        logger.info("\(report, privacy: .public)")
    }

    func makeReport(
        albums: [Album],
        spotlightTitle: String? = nil,
        spotlightArtist: String? = nil
    ) -> String {
        let exactGroups = groupDuplicates(
            albums: albums,
            keyBuilder: { album in
                "\(normalize(album.artistName))|\(normalize(album.title))|\(album.year?.description ?? "")"
            }
        )

        let candidateGroups = groupDuplicates(
            albums: albums,
            keyBuilder: { album in
                "\(normalize(album.artistName))|\(normalize(album.title))"
            }
        )

        let spotlightMatches = albums.filter { album in
            if let spotlightTitle, !normalize(album.title).contains(normalize(spotlightTitle)) {
                return false
            }

            if let spotlightArtist, !normalize(album.artistName).contains(normalize(spotlightArtist)) {
                return false
            }

            return true
        }.sorted(by: albumSort)

        var lines: [String] = []
        lines.append("========== LUNARA DUPLICATE ALBUM DEBUG REPORT ==========")
        lines.append("Album count: \(albums.count)")
        lines.append("Exact duplicate groups (artist + title + year): \(exactGroups.count)")

        if exactGroups.isEmpty {
            lines.append("  none")
        } else {
            lines.append(contentsOf: describe(groups: exactGroups))
        }

        lines.append("Candidate duplicate groups (artist + title, year ignored): \(candidateGroups.count)")
        if candidateGroups.isEmpty {
            lines.append("  none")
        } else {
            lines.append(contentsOf: describe(groups: candidateGroups))
        }

        if spotlightTitle != nil || spotlightArtist != nil {
            lines.append("Spotlight matches:")
            if spotlightMatches.isEmpty {
                lines.append("  none")
            } else {
                for album in spotlightMatches {
                    lines.append("  - \(albumLine(album))")
                }
            }
        }

        lines.append("========================================================")
        return lines.joined(separator: "\n")
    }

    private func groupDuplicates(
        albums: [Album],
        keyBuilder: (Album) -> String
    ) -> [[Album]] {
        let grouped = Dictionary(grouping: albums, by: keyBuilder)
        return grouped.values
            .filter { $0.count > 1 }
            .map { $0.sorted(by: albumSort) }
            .sorted { lhs, rhs in
                guard let lhsFirst = lhs.first, let rhsFirst = rhs.first else {
                    return lhs.count > rhs.count
                }
                return albumSort(lhsFirst, rhsFirst)
            }
    }

    private func describe(groups: [[Album]]) -> [String] {
        var lines: [String] = []

        for (index, group) in groups.enumerated() {
            guard let first = group.first else {
                continue
            }

            lines.append("  [\(index + 1)] \(first.artistName) - \(first.title) (\(group.count) entries)")
            for album in group {
                lines.append("      - \(albumLine(album))")
            }
        }

        return lines
    }

    private func albumLine(_ album: Album) -> String {
        "id=\(album.plexID), year=\(album.year.map(String.init) ?? "nil"), trackCount=\(album.trackCount), duration=\(Int(album.duration))s"
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func albumSort(_ lhs: Album, _ rhs: Album) -> Bool {
        if lhs.artistName != rhs.artistName {
            return lhs.artistName.localizedCaseInsensitiveCompare(rhs.artistName) == .orderedAscending
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        if lhs.year != rhs.year {
            return (lhs.year ?? Int.min) < (rhs.year ?? Int.min)
        }
        return lhs.plexID < rhs.plexID
    }
}
