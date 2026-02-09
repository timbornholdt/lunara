import Foundation
import Testing
@testable import Lunara

struct PlexAuthTokenStoreTests {
    @Test func savesLoadsAndClearsToken() throws {
        let keychain = InMemoryKeychain()
        let store = PlexAuthTokenStore(keychain: keychain)

        try store.save(token: "token")
        #expect(try store.load() == "token")

        try store.clear()
        #expect(try store.load() == nil)
    }
}

private final class InMemoryKeychain: KeychainStoring {
    private var storage: [String: String] = [:]

    func save(key: String, value: String) throws {
        storage[key] = value
    }

    func read(key: String) throws -> String? {
        storage[key]
    }

    func delete(key: String) throws {
        storage.removeValue(forKey: key)
    }
}
