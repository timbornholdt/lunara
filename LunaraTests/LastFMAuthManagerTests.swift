import Foundation
import Testing
@testable import Lunara

@MainActor
@Suite
struct LastFMAuthManagerTests {

    @Test
    func initialState_isNotAuthenticated() {
        let keychain = MockKeychainHelper()
        let client = LastFMClientMock()
        let manager = LastFMAuthManager(client: client, keychain: keychain, urlOpener: URLOpenerMock())

        #expect(!manager.isAuthenticated)
        #expect(manager.username == nil)
    }

    @Test
    func initialState_restoresSessionFromKeychain() throws {
        let keychain = MockKeychainHelper()
        try keychain.save(key: "lastfm_session_key", string: "stored-key")
        try keychain.save(key: "lastfm_username", string: "stored-user")
        let client = LastFMClientMock()
        let manager = LastFMAuthManager(client: client, keychain: keychain, urlOpener: URLOpenerMock())

        #expect(manager.isAuthenticated)
        #expect(manager.username == "stored-user")
    }

    @Test
    func authenticate_getsTokenAndOpensSafari() async throws {
        let keychain = MockKeychainHelper()
        let client = LastFMClientMock()
        client.getTokenResult = .success("my-token")
        let opener = URLOpenerMock()
        let manager = LastFMAuthManager(client: client, keychain: keychain, urlOpener: opener)

        try await manager.authenticate()

        #expect(client.getTokenCallCount == 1)
        #expect(opener.openedURLs.count == 1)
        #expect(opener.openedURLs.first?.absoluteString.contains("my-token") == true)
    }

    @Test
    func handleCallback_exchangesTokenAndStoresSession() async throws {
        let keychain = MockKeychainHelper()
        let client = LastFMClientMock()
        client.getSessionResult = .success(("session-abc", "bob"))
        let manager = LastFMAuthManager(client: client, keychain: keychain, urlOpener: URLOpenerMock())

        let callbackURL = URL(string: "lunara://lastfm-callback?token=my-token")!
        try await manager.handleCallback(url: callbackURL)

        #expect(manager.isAuthenticated)
        #expect(manager.username == "bob")
        #expect(try keychain.retrieveString(key: "lastfm_session_key") == "session-abc")
        #expect(client.getSessionCalls == ["my-token"])
    }

    @Test
    func signOut_clearsKeychainAndState() async throws {
        let keychain = MockKeychainHelper()
        try keychain.save(key: "lastfm_session_key", string: "key")
        try keychain.save(key: "lastfm_username", string: "user")
        let client = LastFMClientMock()
        let manager = LastFMAuthManager(client: client, keychain: keychain, urlOpener: URLOpenerMock())

        #expect(manager.isAuthenticated)
        manager.signOut()

        #expect(!manager.isAuthenticated)
        #expect(manager.username == nil)
        #expect(try keychain.retrieveString(key: "lastfm_session_key") == nil)
    }
}
