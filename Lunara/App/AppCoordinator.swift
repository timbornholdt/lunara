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

        let libraryRepo = plexClient
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
        try await libraryRepo.fetchAlbums()
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
}
