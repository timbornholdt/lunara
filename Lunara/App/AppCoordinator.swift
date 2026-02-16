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

    // MARK: - State

    var isSignedIn: Bool {
        authManager.isSignedIn
    }

    // MARK: - Initialization

    init() {
        // Initialize dependencies
        let keychain = KeychainHelper()
        self.authManager = AuthManager(keychain: keychain)

        // Load server URL from LocalConfig or use default
        let serverURL = Self.loadServerURL()

        // Create PlexAPIClient that conforms to PlexAuthAPIProtocol
        self.plexClient = PlexAPIClient(
            baseURL: serverURL,
            authManager: authManager,
            session: URLSession.shared
        )

        // Update AuthManager to use this PlexAPIClient for OAuth
        // Note: This creates a slight circular reference, but it's safe because
        // AuthManager holds PlexAuthAPIProtocol? (optional) and only uses it for OAuth
        self.authManager = AuthManager(
            keychain: keychain,
            authAPI: plexClient
        )
    }

    // MARK: - Actions

    /// Sign out and clear stored token
    func signOut() {
        try? authManager.clearToken()
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
