import Foundation
import Combine
import SwiftUI
#if DEBUG
import os
#endif

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var login: String = ""
    @Published var password: String = ""
    @Published var serverURLText: String = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isAuthenticated = false

    private let tokenStore: PlexAuthTokenStoring
    private var serverStore: PlexServerAddressStoring
    private let authService: PlexAuthServicing
    private let tokenValidator: PlexTokenValidating
    private let loadOnInit: Bool

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        authService: PlexAuthServicing = PlexAuthService(
            httpClient: PlexHTTPClient(),
            requestBuilder: PlexAuthRequestBuilder(
                baseURL: PlexDefaults.authBaseURL,
                configuration: PlexDefaults.configuration()
            )
        ),
        tokenValidator: PlexTokenValidating = PlexTokenValidator(
            libraryServiceFactory: { serverURL, token in
                let config = PlexDefaults.configuration()
                let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
                return PlexLibraryService(
                    httpClient: PlexHTTPClient(),
                    requestBuilder: builder,
                    paginator: PlexPaginator(pageSize: 50)
                )
            }
        ),
        loadOnInit: Bool = true
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.authService = authService
        self.tokenValidator = tokenValidator
        self.loadOnInit = loadOnInit
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
            let token = try await authService.signIn(
                login: login,
                password: password,
                verificationCode: nil,
                rememberMe: true
            )
            try tokenStore.save(token: token)
            serverStore.serverURL = serverURL
            isAuthenticated = true
        } catch {
#if DEBUG
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lunara", category: "Auth")
                .error("Sign in failed: \(String(describing: error))")
#endif
            errorMessage = "Sign in failed."
        }
    }

    func signOut() {
        do {
            try tokenStore.clear()
        } catch {
            errorMessage = "Failed to sign out."
        }
        isAuthenticated = false
    }

#if DEBUG
    func applyLocalCredentialsIfAvailable() {
        guard let credentials = LocalPlexConfig.credentials else { return }
        login = credentials.username
        password = credentials.password
        serverURLText = credentials.serverURL
    }

    func signInWithLocalConfig() async {
        applyLocalCredentialsIfAvailable()
        await signIn()
    }
#endif
}
