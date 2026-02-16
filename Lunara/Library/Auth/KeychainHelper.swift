import Foundation
import Security

// MARK: - KeychainHelperProtocol

/// Protocol for Keychain operations, allowing mock implementations in tests
protocol KeychainHelperProtocol {
    func save(key: String, data: Data) throws
    func retrieve(key: String) throws -> Data?
    func delete(key: String) throws
}

// MARK: - KeychainHelper

/// Wraps iOS Keychain operations for secure credential storage
final class KeychainHelper: KeychainHelperProtocol {

    enum KeychainError: Error {
        case saveFailed(status: OSStatus)
        case retrieveFailed(status: OSStatus)
        case deleteFailed(status: OSStatus)
        case unexpectedData
    }

    private let service: String

    /// - Parameter service: Bundle identifier or unique service name for Keychain items
    init(service: String = Bundle.main.bundleIdentifier ?? "holdings.chinlock.Lunara") {
        self.service = service
    }

    // MARK: - KeychainHelperProtocol

    func save(key: String, data: Data) throws {
        // Build query for this key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success if deleted or if item didn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - Convenience String Extensions

extension KeychainHelperProtocol {
    /// Save a string to Keychain (UTF-8 encoded)
    func save(key: String, string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainHelper.KeychainError.unexpectedData
        }
        try save(key: key, data: data)
    }

    /// Retrieve a string from Keychain (UTF-8 decoded)
    func retrieveString(key: String) throws -> String? {
        guard let data = try retrieve(key: key) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainHelper.KeychainError.unexpectedData
        }
        return string
    }
}
