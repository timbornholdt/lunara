import XCTest
@testable import Lunara

// MARK: - Mock Keychain

final class MockKeychainHelper: KeychainHelperProtocol {
    private var storage: [String: Data] = [:]

    func save(key: String, data: Data) throws {
        storage[key] = data
    }

    func retrieve(key: String) throws -> Data? {
        return storage[key]
    }

    func delete(key: String) throws {
        storage.removeValue(forKey: key)
    }

    func clear() {
        storage.removeAll()
    }
}

// MARK: - Mock Plex Auth API

final class MockPlexAuthAPI: PlexAuthAPIProtocol {
    var pinToReturn: PlexPinResponse?
    var tokenToReturn: String?
    var shouldThrowError = false
    var checkPinCallCount = 0

    func requestPin() async throws -> PlexPinResponse {
        if shouldThrowError {
            throw LibraryError.plexUnreachable
        }
        return pinToReturn ?? PlexPinResponse(id: 12345, code: "ABCD")
    }

    func checkPin(pinID: Int) async throws -> String? {
        checkPinCallCount += 1
        if shouldThrowError {
            throw LibraryError.plexUnreachable
        }
        return tokenToReturn
    }
}

// MARK: - AuthManager Tests

final class AuthManagerTests: XCTestCase {

    var mockKeychain: MockKeychainHelper!
    var mockAuthAPI: MockPlexAuthAPI!
    var authManager: AuthManager!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainHelper()
        mockAuthAPI = MockPlexAuthAPI()
        authManager = AuthManager(
            keychain: mockKeychain,
            authAPI: mockAuthAPI,
            pollInterval: 0.1,
            pollTimeout: 1.0,
            debugTokenProvider: { nil }
        )
    }

    override func tearDown() {
        mockKeychain = nil
        mockAuthAPI = nil
        authManager = nil
        super.tearDown()
    }

    // MARK: - validToken() Tests

    func test_validToken_withNoToken_throwsAuthExpired() async {
        do {
            _ = try await authManager.validToken()
            XCTFail("Should throw authExpired")
        } catch let error as LibraryError {
            if case .authExpired = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_validToken_withStoredToken_returnsToken() async throws {
        let testToken = "stored_token_abc123"
        try authManager.setToken(testToken)

        let token = try await authManager.validToken()

        XCTAssertEqual(token, testToken)
    }

    func test_validToken_afterInvalidation_throwsAuthExpired() async throws {
        try authManager.setToken("valid_token")

        authManager.invalidateToken()

        do {
            _ = try await authManager.validToken()
            XCTFail("Should throw authExpired")
        } catch let error as LibraryError {
            if case .authExpired = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Token Management Tests

    func test_setToken_storesInKeychain() throws {
        let testToken = "my_test_token"

        try authManager.setToken(testToken)

        let stored = try mockKeychain.retrieveString(key: "plex_auth_token")
        XCTAssertEqual(stored, testToken)
    }

    func test_clearToken_removesFromKeychain() throws {
        try authManager.setToken("token_to_clear")

        try authManager.clearToken()

        let stored = try mockKeychain.retrieveString(key: "plex_auth_token")
        XCTAssertNil(stored)
    }

    func test_clearToken_updatesSignedInStatus() throws {
        try authManager.setToken("token")
        XCTAssertTrue(authManager.isSignedIn)

        try authManager.clearToken()

        XCTAssertFalse(authManager.isSignedIn)
    }

    // MARK: - isSignedIn Tests

    func test_isSignedIn_withNoToken_returnsFalse() {
        XCTAssertFalse(authManager.isSignedIn)
    }

    func test_isSignedIn_withToken_returnsTrue() throws {
        try authManager.setToken("valid_token")
        XCTAssertTrue(authManager.isSignedIn)
    }

    func test_isSignedIn_afterInvalidation_returnsFalse() throws {
        try authManager.setToken("valid_token")
        authManager.invalidateToken()
        XCTAssertFalse(authManager.isSignedIn)
    }

    // MARK: - OAuth Flow Tests

    func test_startAuthFlow_requestsPin_returnsCode() async throws {
        mockAuthAPI.pinToReturn = PlexPinResponse(id: 999, code: "WXYZ")

        let code = try await authManager.startAuthFlow()

        XCTAssertEqual(code, "WXYZ")
    }

    func test_startAuthFlow_withoutAuthAPI_throwsError() async {
        let authManagerWithoutAPI = AuthManager(
            keychain: mockKeychain,
            authAPI: nil,
            debugTokenProvider: { nil }
        )

        do {
            _ = try await authManagerWithoutAPI.startAuthFlow()
            XCTFail("Should throw error")
        } catch let error as LibraryError {
            if case .operationFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_startAuthFlow_pollsForAuthorization_storesToken() async throws {
        mockAuthAPI.pinToReturn = PlexPinResponse(id: 123, code: "TEST")
        mockAuthAPI.tokenToReturn = "authorized_token_xyz"

        _ = try await authManager.startAuthFlow()

        // Wait for polling to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let storedToken = try mockKeychain.retrieveString(key: "plex_auth_token")
        XCTAssertEqual(storedToken, "authorized_token_xyz")
        XCTAssertTrue(authManager.isSignedIn)
    }

    func test_startAuthFlow_pollingTimeout_doesNotStoreToken() async throws {
        mockAuthAPI.pinToReturn = PlexPinResponse(id: 123, code: "TEST")
        mockAuthAPI.tokenToReturn = nil // Never returns a token

        _ = try await authManager.startAuthFlow()

        // Wait for timeout (1 second in our test config)
        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds

        let storedToken = try mockKeychain.retrieveString(key: "plex_auth_token")
        XCTAssertNil(storedToken)
    }

    // MARK: - Invalidation Tests

    func test_invalidateToken_marksTokenAsInvalid() throws {
        try authManager.setToken("valid_token")
        XCTAssertTrue(authManager.isSignedIn)

        authManager.invalidateToken()

        XCTAssertFalse(authManager.isSignedIn)
    }

    func test_invalidateToken_tokenStillInKeychain_butNotValid() async throws {
        try authManager.setToken("token_in_keychain")

        authManager.invalidateToken()

        // Token still in keychain
        let stored = try mockKeychain.retrieveString(key: "plex_auth_token")
        XCTAssertEqual(stored, "token_in_keychain")

        // But validToken() throws
        do {
            _ = try await authManager.validToken()
            XCTFail("Should throw")
        } catch {
            // Expected
        }
    }

    // MARK: - Init with Cached Token Tests

    func test_init_loadsExistingTokenFromKeychain() async throws {
        // Pre-populate keychain
        try mockKeychain.save(key: "plex_auth_token", string: "existing_token")

        // Create new AuthManager (should load from keychain)
        let newAuthManager = AuthManager(
            keychain: mockKeychain,
            authAPI: mockAuthAPI,
            debugTokenProvider: { nil }
        )

        let token = try await newAuthManager.validToken()
        XCTAssertEqual(token, "existing_token")
    }
}
