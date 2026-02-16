import XCTest
@testable import Lunara

final class CollectionTests: XCTestCase {

    // MARK: - subtitle Tests

    func test_subtitle_withSingleAlbum_usesSingularForm() {
        let collection = Collection(
            plexID: "1",
            title: "Test Collection",
            thumbURL: nil,
            summary: nil,
            albumCount: 1,
            updatedAt: nil
        )

        XCTAssertEqual(collection.subtitle, "1 album")
    }

    func test_subtitle_withMultipleAlbums_usesPluralForm() {
        let collection = Collection(
            plexID: "1",
            title: "Test Collection",
            thumbURL: nil,
            summary: nil,
            albumCount: 42,
            updatedAt: nil
        )

        XCTAssertEqual(collection.subtitle, "42 albums")
    }

    func test_subtitle_withZeroAlbums_usesPluralForm() {
        let collection = Collection(
            plexID: "1",
            title: "Empty Collection",
            thumbURL: nil,
            summary: nil,
            albumCount: 0,
            updatedAt: nil
        )

        XCTAssertEqual(collection.subtitle, "0 albums")
    }

    // MARK: - isPinnedCollection Tests

    func test_isPinnedCollection_withCurrentVibes_returnsTrue() {
        let collection = Collection(
            plexID: "1",
            title: "Current Vibes",
            thumbURL: nil,
            summary: nil,
            albumCount: 25,
            updatedAt: nil
        )

        XCTAssertTrue(collection.isPinnedCollection)
    }

    func test_isPinnedCollection_withTheKeyAlbums_returnsTrue() {
        let collection = Collection(
            plexID: "1",
            title: "The Key Albums",
            thumbURL: nil,
            summary: nil,
            albumCount: 50,
            updatedAt: nil
        )

        XCTAssertTrue(collection.isPinnedCollection)
    }

    func test_isPinnedCollection_withOtherTitle_returnsFalse() {
        let collection = Collection(
            plexID: "1",
            title: "My Favorite Albums",
            thumbURL: nil,
            summary: nil,
            albumCount: 30,
            updatedAt: nil
        )

        XCTAssertFalse(collection.isPinnedCollection)
    }

    func test_isPinnedCollection_isCaseSensitive() {
        let collection = Collection(
            plexID: "1",
            title: "current vibes", // lowercase
            thumbURL: nil,
            summary: nil,
            albumCount: 25,
            updatedAt: nil
        )

        XCTAssertFalse(collection.isPinnedCollection)
    }

    // MARK: - Identifiable Tests

    func test_id_matchesPlexID() {
        let collection = Collection(
            plexID: "collection-999",
            title: "Test Collection",
            thumbURL: nil,
            summary: nil,
            albumCount: 10,
            updatedAt: nil
        )

        XCTAssertEqual(collection.id, "collection-999")
    }

    // MARK: - Codable Tests

    func test_codable_encodesAndDecodesCorrectly() throws {
        let original = Collection(
            plexID: "col-456",
            title: "Current Vibes",
            thumbURL: "https://example.com/collection.jpg",
            summary: "A curated selection of current favorites.",
            albumCount: 15,
            updatedAt: Date(timeIntervalSince1970: 1609459200)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Collection.self, from: encoded)

        XCTAssertEqual(decoded.plexID, original.plexID)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.thumbURL, original.thumbURL)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.albumCount, original.albumCount)
        XCTAssertEqual(decoded.updatedAt, original.updatedAt)
    }
}
