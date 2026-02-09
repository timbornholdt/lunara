import Foundation
import Testing
@testable import Lunara

@MainActor
struct AuthViewModelTests {
    @Test func loadsValidTokenSetsAuthenticated() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let validator = StubTokenValidator(result: .success(()))
        let pinService = StubPinService(
            createResult: .success(PlexPin(id: 1, code: "abcd")),
            checkResults: [PlexPinStatus(id: 1, code: "abcd", authToken: "token")]
        )
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            pinService: pinService,
            tokenValidator: validator,
            resourcesService: StubResourcesService(devices: []),
            loadOnInit: false,
            pollIntervalNanoseconds: 0,
            maxPollAttempts: 1
        )

        await viewModel.loadToken()

        #expect(viewModel.isAuthenticated == true)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.didFinishInitialTokenCheck == true)
    }

    @Test func clearsInvalidTokenOnLaunch() async {
        let tokenStore = InMemoryTokenStore(token: "expired")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let validator = StubTokenValidator(result: .failure(PlexHTTPError.httpStatus(401, Data())))
        let pinService = StubPinService(
            createResult: .success(PlexPin(id: 1, code: "abcd")),
            checkResults: []
        )
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            pinService: pinService,
            tokenValidator: validator,
            resourcesService: StubResourcesService(devices: []),
            loadOnInit: false,
            pollIntervalNanoseconds: 0,
            maxPollAttempts: 1
        )

        await viewModel.loadToken()

        #expect(viewModel.isAuthenticated == false)
        #expect(tokenStore.token == nil)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
        #expect(viewModel.didFinishInitialTokenCheck == true)
    }

    @Test func signInStoresTokenAndServerURL() async {
        let tokenStore = InMemoryTokenStore(token: nil)
        let serverStore = InMemoryServerStore(url: nil)
        let validator = StubTokenValidator(result: .success(()))
        let pinService = StubPinService(
            createResult: .success(PlexPin(id: 1, code: "abcd")),
            checkResults: [PlexPinStatus(id: 1, code: "abcd", authToken: "token-123")]
        )
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            pinService: pinService,
            tokenValidator: validator,
            resourcesService: StubResourcesService(devices: []),
            loadOnInit: false,
            pollIntervalNanoseconds: 0,
            maxPollAttempts: 1
        )
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
        let pinService = StubPinService(
            createResult: .failure(TestError()),
            checkResults: []
        )
        let viewModel = AuthViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            pinService: pinService,
            tokenValidator: validator,
            resourcesService: StubResourcesService(devices: []),
            loadOnInit: false,
            pollIntervalNanoseconds: 0,
            maxPollAttempts: 1
        )
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

private final class StubPinService: PlexPinServicing {
    private let createResult: Result<PlexPin, Error>
    private var checkResults: [PlexPinStatus]
    private var checkIndex = 0

    init(createResult: Result<PlexPin, Error>, checkResults: [PlexPinStatus]) {
        self.createResult = createResult
        self.checkResults = checkResults
    }

    func createPin() async throws -> PlexPin {
        try createResult.get()
    }

    func checkPin(id: Int, code: String) async throws -> PlexPinStatus {
        guard checkIndex < checkResults.count else {
            return PlexPinStatus(id: id, code: code, authToken: nil)
        }
        let status = checkResults[checkIndex]
        checkIndex += 1
        return status
    }
}

private struct StubResourcesService: PlexResourcesServicing {
    let devices: [PlexResourceDevice]
    var error: Error?

    func fetchDevices(token: String) async throws -> [PlexResourceDevice] {
        if let error { throw error }
        return devices
    }
}
