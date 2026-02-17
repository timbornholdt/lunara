import Foundation
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
    let artworkPipeline: ArtworkPipelineProtocol
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
        artworkPipeline: ArtworkPipelineProtocol,
        playbackEngine: PlaybackEngineProtocol,
        queueManager: QueueManagerProtocol,
        appRouter: AppRouter
    ) {
        self.authManager = authManager
        self.plexClient = plexClient
        self.libraryRepo = libraryRepo
        self.artworkPipeline = artworkPipeline
        self.playbackEngine = playbackEngine
        self.queueManager = queueManager
        self.appRouter = appRouter
    }

    convenience init() {
        // Initialize dependencies
        let keychain = KeychainHelper()
        let serverURL = Self.loadServerURL()
        let authManager = AuthManager(keychain: keychain)
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

        let artworkPipeline: ArtworkPipelineProtocol
        do {
            artworkPipeline = try Self.makeArtworkPipeline(store: libraryStore)
        } catch {
            fatalError("Failed to initialize ArtworkPipeline: \(error)")
        }

        let libraryRepo = LibraryRepo(remote: plexClient, store: libraryStore, artworkPipeline: artworkPipeline)
        let playbackEngine = AVQueuePlayerEngine(audioSession: AudioSession())
        let queueManager = QueueManager(engine: playbackEngine)
        let appRouter = AppRouter(library: libraryRepo, queue: queueManager)

        self.init(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: libraryRepo,
            artworkPipeline: artworkPipeline,
            playbackEngine: playbackEngine,
            queueManager: queueManager,
            appRouter: appRouter
        )
    }

    // MARK: - Actions

    func loadLibraryOnLaunch() async throws -> [Album] {
        try await syncAlbums(refreshReason: .appLaunch)
    }

    func fetchAlbums() async throws -> [Album] {
        try await syncAlbums(refreshReason: .userInitiated)
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

    private func syncAlbums(refreshReason: LibraryRefreshReason) async throws -> [Album] {
        let cachedAlbums = try await libraryRepo.fetchAlbums()

        do {
            _ = try await libraryRepo.refreshLibrary(reason: refreshReason)
            return try await libraryRepo.fetchAlbums()
        } catch {
            if !cachedAlbums.isEmpty {
                return cachedAlbums
            }
            throw error
        }
    }

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
        let appDirectory = try appDirectory()
        let databaseURL = appDirectory.appendingPathComponent("library.sqlite")
        return try LibraryStore(databaseURL: databaseURL)
    }

    private static func makeArtworkPipeline(store: LibraryStoreProtocol) throws -> ArtworkPipeline {
        let appDirectory = try appDirectory()
        let artworkCacheDirectoryURL = appDirectory.appendingPathComponent("artwork-cache", isDirectory: true)
        return ArtworkPipeline(
            store: store,
            session: URLSession.shared,
            cacheDirectoryURL: artworkCacheDirectoryURL
        )
    }

    private static func appDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LibraryError.operationFailed(reason: "Unable to resolve application support directory.")
        }

        let appDirectory = appSupportURL.appendingPathComponent("Lunara", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory
    }
}
