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

    init() {
        // Initialize dependencies
        let keychain = KeychainHelper()
        let serverURL = Self.loadServerURL()

        // To resolve circular dependency:
        // 1. Create AuthManager without authAPI
        // 2. Create PlexAPIClient with that AuthManager
        // 3. AuthManager's authAPI can be set later if needed,
        //    or we use PlexAPIClient directly for OAuth

        // Create AuthManager (authAPI is optional, defaults to nil)
        self.authManager = AuthManager(keychain: keychain)

        // Create PlexAPIClient (which implements PlexAuthAPIProtocol)
        self.plexClient = PlexAPIClient(
            baseURL: serverURL,
            authManager: authManager,
            session: URLSession.shared
        )

        self.libraryRepo = plexClient
        let playbackEngine = AVQueuePlayerEngine(audioSession: AudioSession())
        self.playbackEngine = playbackEngine
        let queueManager = QueueManager(engine: playbackEngine)
        self.queueManager = queueManager
        self.appRouter = AppRouter(library: libraryRepo, queue: queueManager)
    }

    // MARK: - Actions

    func fetchAlbums() async throws -> [Album] {
        try await libraryRepo.fetchAlbums()
    }

    func playAlbum(_ album: Album) async throws {
        try await appRouter.playAlbum(album)
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
