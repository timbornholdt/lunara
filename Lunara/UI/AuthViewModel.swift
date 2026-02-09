import Foundation
import Combine
import SwiftUI
#if DEBUG
import os
#endif

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var serverURLText: String = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var authURL: URL?

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
        guard let serverURL = URL(string: serverURLText), serverURL.scheme != nil else {
            errorMessage = "Enter a valid Plex server URL."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let pin = try await pinService.createPin()
            let config = PlexDefaults.configuration()
            if let url = authURLBuilder.makeAuthURL(
                code: pin.code,
                clientIdentifier: config.clientIdentifier,
                product: config.product
            ) {
                authURL = url
            }
            await pollForToken(pin: pin, serverURL: serverURL)
        } catch {
#if DEBUG
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lunara", category: "Auth")
                .error("Sign in failed: \(String(describing: error))")
#endif
            errorMessage = "Sign in failed."
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
    }

#if DEBUG
    func applyLocalConfigIfAvailable() {
        guard let config = LocalPlexConfig.credentials else { return }
        serverURLText = config.serverURL
    }

    func signInWithLocalConfig() async {
        applyLocalConfigIfAvailable()
        await signIn()
    }
#endif

    private func pollForToken(pin: PlexPin, serverURL: URL) async {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<maxPollAttempts {
                if Task.isCancelled { return }
                do {
                    let status = try await pinService.checkPin(id: pin.id, code: pin.code)
                    if let token = status.authToken {
                        try tokenStore.save(token: token)
                        serverStore.serverURL = serverURL
                        isAuthenticated = true
                        return
                    }
                } catch {
                    if PlexErrorHelpers.isUnauthorized(error) {
                        errorMessage = "Session expired. Please sign in again."
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
            errorMessage = "Sign in timed out."
        }
        await pollTask?.value
    }
}
