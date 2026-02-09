import Foundation

protocol KeychainStoring {
    func save(key: String, value: String) throws
    func read(key: String) throws -> String?
    func delete(key: String) throws
}

struct PlexAuthTokenStore: PlexAuthTokenStoring {
    private let keychain: KeychainStoring
    private let tokenKey = "plex.auth.token"

    init(keychain: KeychainStoring) {
        self.keychain = keychain
    }

    func save(token: String) throws {
        try keychain.save(key: tokenKey, value: token)
    }

    func load() throws -> String? {
        try keychain.read(key: tokenKey)
    }

    func clear() throws {
        try keychain.delete(key: tokenKey)
    }
}
