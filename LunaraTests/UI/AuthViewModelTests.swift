import Foundation
import Testing
@testable import Lunara

@MainActor
struct AuthViewModelTests {
    @Test func loadsValidTokenSetsAuthenticated() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let validator = StubTokenValidator(result: .success(()))
        let authService = StubAuthService(result: .success("token"))
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            authService: authService,
            tokenValidator: validator,
            loadOnInit: false
        )

        await viewModel.loadToken()

        #expect(viewModel.isAuthenticated == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func clearsInvalidTokenOnLaunch() async {
        let tokenStore = InMemoryTokenStore(token: "expired")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let validator = StubTokenValidator(result: .failure(PlexHTTPError.httpStatus(401, Data())))
        let authService = StubAuthService(result: .success("token"))
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            authService: authService,
            tokenValidator: validator,
            loadOnInit: false
        )

        await viewModel.loadToken()

        #expect(viewModel.isAuthenticated == false)
        #expect(tokenStore.token == nil)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
    }

    @Test func signInStoresTokenAndServerURL() async {
        let tokenStore = InMemoryTokenStore(token: nil)
        let serverStore = InMemoryServerStore(url: nil)
        let validator = StubTokenValidator(result: .success(()))
        let authService = StubAuthService(result: .success("token-123"))
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            authService: authService,
            tokenValidator: validator,
            loadOnInit: false
        )
        viewModel.login = "user@example.com"
        viewModel.password = "secret"
        viewModel.serverURLText = "https://example.com:32400"

        await viewModel.signIn()

        #expect(viewModel.isAuthenticated == true)
        #expect(tokenStore.token == "token-123")
        #expect(serverStore.url?.absoluteString == "https://example.com:32400")
    }

    @Test func signInFailureSurfacesError() async {
        let tokenStore = InMemoryTokenStore(token: nil)
        let serverStore = InMemoryServerStore(url: nil)
        let validator = StubTokenValidator(result: .success(()))
        let authService = StubAuthService(result: .failure(TestError()))
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            authService: authService,
            tokenValidator: validator,
            loadOnInit: false
        )
        viewModel.login = "user@example.com"
        viewModel.password = "secret"
        viewModel.serverURLText = "https://example.com:32400"

        await viewModel.signIn()

        #expect(viewModel.isAuthenticated == false)
        #expect(viewModel.errorMessage == "Sign in failed.")
    }
}

private struct TestError: Error {}

private struct StubTokenValidator: PlexTokenValidating {
    let result: Result<Void, Error>

    func validate(serverURL: URL, token: String) async throws {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

private struct StubAuthService: PlexAuthServicing {
    let result: Result<String, Error>

    func signIn(
        login: String,
        password: String,
        verificationCode: String?,
        rememberMe: Bool
    ) async throws -> String {
        switch result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        }
    }
}
