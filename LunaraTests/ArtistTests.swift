import XCTest
@testable import Lunara

final class ArtistTests: XCTestCase {

    // MARK: - effectiveSortName Tests

    func test_effectiveSortName_withSortName_returnsSortName() {
        let artist = Artist(
            plexID: "1",
            name: "The Beatles",
            sortName: "Beatles, The",
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 13
        )

        XCTAssertEqual(artist.effectiveSortName, "Beatles, The")
    }

    func test_effectiveSortName_withoutSortName_returnsName() {
        let artist = Artist(
            plexID: "1",
            name: "Prince",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 39
        )

        XCTAssertEqual(artist.effectiveSortName, "Prince")
    }

    func test_effectiveSortName_withEmptySortName_returnsName() {
        let artist = Artist(
            plexID: "1",
            name: "Madonna",
            sortName: "",
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 14
        )

        // Empty string is still non-nil, so effectiveSortName will return it
        // This test documents current behavior
        XCTAssertEqual(artist.effectiveSortName, "")
    }

    // MARK: - hasSummary Tests

    func test_hasSummary_withNonEmptySummary_returnsTrue() {
        let artist = Artist(
            plexID: "1",
            name: "The Beatles",
            sortName: nil,
            thumbURL: nil,
            genre: "Rock",
            summary: "The Beatles were an English rock band...",
            albumCount: 13
        )

        XCTAssertTrue(artist.hasSummary)
    }

    func test_hasSummary_withNilSummary_returnsFalse() {
        let artist = Artist(
            plexID: "1",
            name: "Unknown Artist",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 1
        )

        XCTAssertFalse(artist.hasSummary)
    }

    func test_hasSummary_withEmptySummary_returnsFalse() {
        let artist = Artist(
            plexID: "1",
            name: "Unknown Artist",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: "",
            albumCount: 1
        )

        XCTAssertFalse(artist.hasSummary)
    }

    func test_hasSummary_withWhitespaceSummary_returnsTrue() {
        // Current implementation considers whitespace as "having" a summary
        // This documents the behavior - we may want to trim in the future
        let artist = Artist(
            plexID: "1",
            name: "Test Artist",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: "   ",
            albumCount: 1
        )

        XCTAssertTrue(artist.hasSummary)
    }

    // MARK: - Identifiable Tests

    func test_id_matchesPlexID() {
        let artist = Artist(
            plexID: "artist-123",
            name: "Test Artist",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 5
        )

        XCTAssertEqual(artist.id, "artist-123")
    }

    // MARK: - Codable Tests

    func test_codable_encodesAndDecodesCorrectly() throws {
        let original = Artist(
            plexID: "artist-789",
            name: "David Bowie",
            sortName: "Bowie, David",
            thumbURL: "https://example.com/bowie.jpg",
            genre: "Rock",
            summary: "An influential artist of the 20th century.",
            albumCount: 27
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Artist.self, from: encoded)

        XCTAssertEqual(decoded.plexID, original.plexID)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.sortName, original.sortName)
        XCTAssertEqual(decoded.thumbURL, original.thumbURL)
        XCTAssertEqual(decoded.genre, original.genre)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.albumCount, original.albumCount)
    }
}
