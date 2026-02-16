import Foundation

// MARK: - AuthManager

/// Manages Plex authentication token lifecycle
/// - Handles pin-based OAuth flow
/// - Stores tokens securely in Keychain
/// - Provides valid tokens to API client
/// - Supports debug quick sign-in via LocalConfig.plist
final class AuthManager {

    // MARK: - Properties

    private let keychain: KeychainHelperProtocol
    private let authAPI: PlexAuthAPIProtocol?
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval
    private let debugTokenProvider: () -> String?

    private static let tokenKey = "plex_auth_token"
    private var cachedToken: String?
    private var tokenIsValid = true

    // MARK: - Initialization

    /// Creates an AuthManager
    /// - Parameters:
    ///   - keychain: Keychain storage implementation (injected for testing)
    ///   - authAPI: Plex auth API implementation (nil for LocalConfig-only mode)
    ///   - pollInterval: How often to check pin authorization (default: 1 second)
    ///   - pollTimeout: How long to wait for user authorization (default: 5 minutes)
    ///   - debugTokenProvider: Optional debug token source (defaults to LocalConfig.plist)
    init(
        keychain: KeychainHelperProtocol = KeychainHelper(),
        authAPI: PlexAuthAPIProtocol? = nil,
        pollInterval: TimeInterval = 1.0,
        pollTimeout: TimeInterval = 300.0,
        debugTokenProvider: @escaping () -> String? = { AuthManager.loadDebugTokenFromBundle() }
    ) {
        self.keychain = keychain
        self.authAPI = authAPI
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.debugTokenProvider = debugTokenProvider

        // Load cached token from Keychain on init
        self.cachedToken = try? keychain.retrieveString(key: Self.tokenKey)
    }

    // MARK: - Public API

    /// Returns a valid auth token, or throws if no token is available
    /// - Checks LocalConfig.plist first (debug mode)
    /// - Then checks Keychain cache
    /// - Throws authExpired if no token or token marked invalid
    func validToken() async throws -> String {
        // Debug mode: check LocalConfig.plist first
        if let debugToken = debugTokenProvider() {
            return debugToken
        }

        // Check if we have a cached token and it's still marked valid
        guard tokenIsValid, let token = cachedToken else {
            throw LibraryError.authExpired
        }

        return token
    }

    /// Marks the current token as invalid (called by API client on 401)
    /// Next validToken() call will throw authExpired
    func invalidateToken() {
        tokenIsValid = false
    }

    /// Starts the Plex pin-based OAuth flow
    /// - Returns: Pin code to display to user
    /// - Throws: If pin request fails
    func startAuthFlow() async throws -> String {
        guard let authAPI = authAPI else {
            throw LibraryError.operationFailed(reason: "Auth API not configured")
        }

        let pinResponse = try await authAPI.requestPin()

        // Start polling in background
        Task {
            await pollForAuthorization(pinID: pinResponse.id)
        }

        return pinResponse.code
    }

    /// Manually set auth token (for testing or manual configuration)
    func setToken(_ token: String) throws {
        try keychain.save(key: Self.tokenKey, string: token)
        cachedToken = token
        tokenIsValid = true
    }

    /// Clear stored token (sign out)
    func clearToken() throws {
        try keychain.delete(key: Self.tokenKey)
        cachedToken = nil
        tokenIsValid = false
    }

    /// Check if user is currently signed in
    var isSignedIn: Bool {
        cachedToken != nil && tokenIsValid
    }

    // MARK: - Private Helpers

    /// Polls Plex API to check if user has authorized the pin
    private func pollForAuthorization(pinID: Int) async {
        guard let authAPI = authAPI else { return }

        let startTime = Date()

        while Date().timeIntervalSince(startTime) < pollTimeout {
            do {
                if let token = try await authAPI.checkPin(pinID: pinID) {
                    // Got a token! Save it
                    try keychain.save(key: Self.tokenKey, string: token)
                    cachedToken = token
                    tokenIsValid = true
                    return
                }

                // Not authorized yet, wait and try again
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))

            } catch {
                // Network error or other issue - stop polling
                return
            }
        }
    }

    /// Loads debug token from LocalConfig.plist if available
    private static func loadDebugTokenFromBundle() -> String? {
        guard let configPath = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: configPath) as? [String: Any],
              let token = config["PLEX_AUTH_TOKEN"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }
}
