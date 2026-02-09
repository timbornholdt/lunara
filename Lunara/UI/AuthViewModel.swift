import Foundation
import Combine
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var login: String = ""
    @Published var password: String = ""
    @Published var serverURLText: String = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isAuthenticated = false

    private let tokenStore: PlexAuthTokenStore

    init(tokenStore: PlexAuthTokenStore = PlexAuthTokenStore(keychain: KeychainStore())) {
        self.tokenStore = tokenStore
        self.serverURLText = UserDefaults.standard.string(forKey: "plex.server.baseURL") ?? ""
        Task {
            await loadToken()
        }
    }

    func loadToken() async {
        do {
            let token = try tokenStore.load()
            if token != nil {
                isAuthenticated = true
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
            let config = PlexDefaults.configuration()
            let authService = PlexAuthService(
                httpClient: PlexHTTPClient(),
                requestBuilder: PlexAuthRequestBuilder(baseURL: PlexDefaults.authBaseURL, configuration: config)
            )
            let token = try await authService.signIn(
                login: login,
                password: password,
                verificationCode: nil,
                rememberMe: true
            )
            try tokenStore.save(token: token)
            UserDefaults.standard.set(serverURL.absoluteString, forKey: "plex.server.baseURL")
            isAuthenticated = true
        } catch {
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
}
