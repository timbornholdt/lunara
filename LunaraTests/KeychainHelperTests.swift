import XCTest
@testable import Lunara

final class KeychainHelperTests: XCTestCase {

    var keychain: KeychainHelper!
    let testKey = "test_keychain_key"

    override func setUp() {
        super.setUp()
        // Use a test-specific service to avoid conflicts
        keychain = KeychainHelper(service: "com.test.lunara.keychain")

        // Clean up any existing test data
        try? keychain.delete(key: testKey)
    }

    override func tearDown() {
        // Clean up after tests
        try? keychain.delete(key: testKey)
        keychain = nil
        super.tearDown()
    }

    // MARK: - Save and Retrieve Tests

    func test_saveAndRetrieve_withData_succeeds() throws {
        let testData = "test_token_12345".data(using: .utf8)!

        try keychain.save(key: testKey, data: testData)
        let retrieved = try keychain.retrieve(key: testKey)

        XCTAssertEqual(retrieved, testData)
    }

    func test_saveAndRetrieve_withString_succeeds() throws {
        let testString = "my_auth_token"

        try keychain.save(key: testKey, string: testString)
        let retrieved = try keychain.retrieveString(key: testKey)

        XCTAssertEqual(retrieved, testString)
    }

    func test_retrieve_nonExistentKey_returnsNil() throws {
        let retrieved = try keychain.retrieve(key: "non_existent_key")
        XCTAssertNil(retrieved)
    }

    func test_save_overwritesExistingValue() throws {
        let firstValue = "first_token"
        let secondValue = "second_token"

        try keychain.save(key: testKey, string: firstValue)
        try keychain.save(key: testKey, string: secondValue)

        let retrieved = try keychain.retrieveString(key: testKey)
        XCTAssertEqual(retrieved, secondValue)
    }

    // MARK: - Delete Tests

    func test_delete_existingKey_succeeds() throws {
        try keychain.save(key: testKey, string: "test_value")

        try keychain.delete(key: testKey)

        let retrieved = try keychain.retrieve(key: testKey)
        XCTAssertNil(retrieved)
    }

    func test_delete_nonExistentKey_doesNotThrow() throws {
        // Deleting a non-existent key should not throw
        XCTAssertNoThrow(try keychain.delete(key: "non_existent_key"))
    }

    // MARK: - Unicode and Special Characters

    func test_saveAndRetrieve_withUnicodeCharacters_succeeds() throws {
        let unicodeString = "🔐 Token with émojis and spëcial çhars 中文"

        try keychain.save(key: testKey, string: unicodeString)
        let retrieved = try keychain.retrieveString(key: testKey)

        XCTAssertEqual(retrieved, unicodeString)
    }

    func test_saveAndRetrieve_withLongToken_succeeds() throws {
        // Simulate a long JWT-style token
        let longToken = String(repeating: "a", count: 1000)

        try keychain.save(key: testKey, string: longToken)
        let retrieved = try keychain.retrieveString(key: testKey)

        XCTAssertEqual(retrieved, longToken)
    }
}
