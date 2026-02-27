import Foundation
import UIKit
import os

@MainActor
@Observable
final class LastFMAuthManager {

    private(set) var isAuthenticated = false
    private(set) var username: String?

    private let client: LastFMClientProtocol
    private let keychain: KeychainHelperProtocol
    private let urlOpener: URLOpening
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "LastFMAuthManager")

    private static let sessionKeyKeychainKey = "lastfm_session_key"
    private static let usernameKeychainKey = "lastfm_username"

    /// Pending token from auth.getToken, awaiting callback
    private var pendingToken: String?

    init(
        client: LastFMClientProtocol,
        keychain: KeychainHelperProtocol,
        urlOpener: URLOpening? = nil
    ) {
        self.client = client
        self.keychain = keychain
        self.urlOpener = urlOpener ?? SafariURLOpener()
        loadStoredSession()
    }

    // MARK: - Public

    func authenticate() async throws {
        let token = try await client.getToken()
        pendingToken = token

        let authURLString = "https://www.last.fm/api/auth/?api_key=\(LastFMClient.apiKey)&token=\(token)"
        guard let url = URL(string: authURLString) else {
            throw LastFMError.invalidRequest
        }

        logger.info("Opening Last.fm auth URL: \(url.absoluteString, privacy: .public)")
        urlOpener.openURL(url)
    }

    /// Whether the user has been sent to Safari and we're awaiting their return.
    var hasPendingAuth: Bool { pendingToken != nil }

    /// Called when the app returns to the foreground after the user approved in Safari.
    func completePendingAuthentication() async throws {
        guard let token = pendingToken else {
            throw LastFMError.missingCallbackToken
        }
        try await exchangeToken(token)
    }

    func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value ?? pendingToken else {
            throw LastFMError.missingCallbackToken
        }
        try await exchangeToken(token)
    }

    private func exchangeToken(_ token: String) async throws {
        let result = try await client.getSession(token: token)
        try keychain.save(key: Self.sessionKeyKeychainKey, string: result.sessionKey)
        try keychain.save(key: Self.usernameKeychainKey, string: result.username)
        isAuthenticated = true
        username = result.username
        pendingToken = nil
        logger.info("Last.fm authenticated as \(result.username, privacy: .public)")
    }

    func signOut() {
        do {
            try keychain.delete(key: Self.sessionKeyKeychainKey)
            try keychain.delete(key: Self.usernameKeychainKey)
        } catch {
            logger.error("Failed to clear Last.fm credentials: \(error.localizedDescription, privacy: .public)")
        }
        isAuthenticated = false
        username = nil
        pendingToken = nil
    }

    var sessionKey: String? {
        try? keychain.retrieveString(key: Self.sessionKeyKeychainKey)
    }

    // MARK: - Private

    private func loadStoredSession() {
        guard let _ = try? keychain.retrieveString(key: Self.sessionKeyKeychainKey) else {
            return
        }
        isAuthenticated = true
        username = try? keychain.retrieveString(key: Self.usernameKeychainKey)
    }
}

// MARK: - URL Opening Protocol

protocol URLOpening: Sendable {
    @MainActor
    func openURL(_ url: URL)
}

@MainActor
final class SafariURLOpener: URLOpening, Sendable {
    func openURL(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
