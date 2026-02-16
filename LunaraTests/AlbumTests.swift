import XCTest
@testable import Lunara

final class AlbumTests: XCTestCase {

    // MARK: - formattedDuration Tests

    func test_formattedDuration_withShortDuration_formatsCorrectly() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 5,
            duration: 185 // 3:05
        )

        XCTAssertEqual(album.formattedDuration, "3:05")
    }

    func test_formattedDuration_withLongDuration_formatsCorrectly() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 10,
            duration: 3661 // 61:01
        )

        XCTAssertEqual(album.formattedDuration, "61:01")
    }

    func test_formattedDuration_withZeroDuration_formatsAsZero() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )

        XCTAssertEqual(album.formattedDuration, "0:00")
    }

    func test_formattedDuration_withExactMinute_formatsWithZeroSeconds() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 8,
            duration: 2520 // 42:00
        )

        XCTAssertEqual(album.formattedDuration, "42:00")
    }

    // MARK: - subtitle Tests

    func test_subtitle_withYear_includesYearAndArtist() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "The Beatles",
            year: 1969,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 12,
            duration: 2400
        )

        XCTAssertEqual(album.subtitle, "The Beatles • 1969")
    }

    func test_subtitle_withoutYear_onlyShowsArtist() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "The Beatles",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 12,
            duration: 2400
        )

        XCTAssertEqual(album.subtitle, "The Beatles")
    }

    // MARK: - isRated Tests

    func test_isRated_withPositiveRating_returnsTrue() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: 8,
            addedAt: nil,
            trackCount: 10,
            duration: 2400
        )

        XCTAssertTrue(album.isRated)
    }

    func test_isRated_withZeroRating_returnsFalse() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: 0,
            addedAt: nil,
            trackCount: 10,
            duration: 2400
        )

        XCTAssertFalse(album.isRated)
    }

    func test_isRated_withNilRating_returnsFalse() {
        let album = Album(
            plexID: "1",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 10,
            duration: 2400
        )

        XCTAssertFalse(album.isRated)
    }

    // MARK: - Identifiable Tests

    func test_id_matchesPlexID() {
        let album = Album(
            plexID: "12345",
            title: "Test Album",
            artistName: "Test Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 10,
            duration: 2400
        )

        XCTAssertEqual(album.id, "12345")
    }

    // MARK: - Codable Tests

    func test_codable_encodesAndDecodesCorrectly() throws {
        let original = Album(
            plexID: "123",
            title: "Abbey Road",
            artistName: "The Beatles",
            year: 1969,
            thumbURL: "https://example.com/thumb.jpg",
            genre: "Rock",
            rating: 9,
            addedAt: Date(timeIntervalSince1970: 1609459200),
            trackCount: 17,
            duration: 2843
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Album.self, from: encoded)

        XCTAssertEqual(decoded.plexID, original.plexID)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.artistName, original.artistName)
        XCTAssertEqual(decoded.year, original.year)
        XCTAssertEqual(decoded.thumbURL, original.thumbURL)
        XCTAssertEqual(decoded.genre, original.genre)
        XCTAssertEqual(decoded.rating, original.rating)
        XCTAssertEqual(decoded.addedAt, original.addedAt)
        XCTAssertEqual(decoded.trackCount, original.trackCount)
        XCTAssertEqual(decoded.duration, original.duration)
    }
}
