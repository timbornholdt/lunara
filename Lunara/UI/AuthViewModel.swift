import Foundation
import Combine
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var serverURLText: String = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var authURL: URL?
    @Published var statusMessage: String?
#if DEBUG
    @Published var debugLog: [String] = []
#endif

    private let tokenStore: PlexAuthTokenStoring
    private var serverStore: PlexServerAddressStoring
    private let pinService: PlexPinServicing
    private let authURLBuilder: PlexAuthURLBuilder
    private let tokenValidator: PlexTokenValidating
    private let loadOnInit: Bool
    private let pollIntervalNanoseconds: UInt64
    private let maxPollAttempts: Int
    private var pollTask: Task<Void, Never>?

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        pinService: PlexPinServicing = PlexPinService(
            httpClient: PlexHTTPClient(),
            requestBuilder: PlexPinRequestBuilder(
                baseURL: PlexDefaults.authBaseURL,
                configuration: PlexDefaults.configuration()
            )
        ),
        authURLBuilder: PlexAuthURLBuilder = PlexAuthURLBuilder(),
        tokenValidator: PlexTokenValidating = PlexTokenValidator(
            httpClient: PlexHTTPClient(),
            configuration: PlexDefaults.configuration()
        ),
        loadOnInit: Bool = true,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        maxPollAttempts: Int = 120
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.pinService = pinService
        self.authURLBuilder = authURLBuilder
        self.tokenValidator = tokenValidator
        self.loadOnInit = loadOnInit
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPollAttempts = maxPollAttempts
        self.serverURLText = serverStore.serverURL?.absoluteString ?? ""
        if loadOnInit {
            Task {
                await loadToken()
            }
        }
    }

    func loadToken() async {
        do {
            guard let token = try tokenStore.load() else { return }
            guard let serverURL = serverStore.serverURL else {
                errorMessage = "Missing server URL."
                return
            }
            do {
                try await tokenValidator.validate(serverURL: serverURL, token: token)
                isAuthenticated = true
            } catch {
                if PlexErrorHelpers.isUnauthorized(error) {
                    try? tokenStore.clear()
                    errorMessage = "Session expired. Please sign in again."
                } else {
                    errorMessage = "Failed to validate session."
                }
                isAuthenticated = false
            }
        } catch {
            errorMessage = "Failed to load session."
        }
    }

    func signIn() async {
        errorMessage = nil
        statusMessage = "Preparing sign-in..."
        guard let serverURL = URL(string: serverURLText), serverURL.scheme != nil else {
            errorMessage = "Enter a valid Plex server URL."
            statusMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            log("Creating Plex PIN...")
            let pin = try await pinService.createPin()
            log("PIN created. Building auth URL.")
            let config = PlexDefaults.configuration()
            if let url = authURLBuilder.makeAuthURL(
                code: pin.code,
                clientIdentifier: config.clientIdentifier,
                product: config.product,
                forwardURL: URL(string: "https://app.plex.tv/desktop/")
            ) {
                authURL = url
                statusMessage = "Waiting for authorization..."
                log("Auth URL ready: \(url.absoluteString)")
            }
            await pollForToken(pin: pin, serverURL: serverURL)
        } catch {
            errorMessage = "Sign in failed."
            statusMessage = nil
        }
    }

    func signOut() {
        pollTask?.cancel()
        do {
            try tokenStore.clear()
        } catch {
            errorMessage = "Failed to sign out."
        }
        isAuthenticated = false
        statusMessage = nil
    }

#if DEBUG
    func applyLocalConfigIfAvailable() {
        guard let config = LocalPlexConfig.credentials else { return }
        serverURLText = config.serverURL
        log("Loaded LocalConfig.plist server URL.")
    }

    func signInWithLocalConfig() async {
        applyLocalConfigIfAvailable()
        await signIn()
    }
#endif

    private func pollForToken(pin: PlexPin, serverURL: URL) async {
        pollTask?.cancel()
        pollTask = Task {
            for attempt in 1...maxPollAttempts {
                if Task.isCancelled { return }
                do {
                    if attempt == 1 || attempt % 5 == 0 {
                        log("Polling for auth token (attempt \(attempt))...")
                    }
                    let status = try await pinService.checkPin(id: pin.id, code: pin.code)
                    if let token = status.authToken {
                        log("Authorization complete. Saving token.")
                        try tokenStore.save(token: token)
                        serverStore.serverURL = serverURL
                        isAuthenticated = true
                        statusMessage = "Signed in."
                        return
                    }
                } catch {
                    log("Polling error: \(String(describing: error))")
                    if PlexErrorHelpers.isUnauthorized(error) {
                        errorMessage = "Session expired. Please sign in again."
                        statusMessage = nil
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
            errorMessage = "Sign in timed out."
            statusMessage = nil
        }
        await pollTask?.value
    }

#if DEBUG
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        debugLog.append("[\(timestamp)] \(message)")
    }
#endif
}
