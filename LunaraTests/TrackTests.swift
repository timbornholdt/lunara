import XCTest
@testable import Lunara

final class TrackTests: XCTestCase {

    // MARK: - formattedDuration Tests

    func test_formattedDuration_withShortDuration_formatsCorrectly() {
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "Test Track",
            trackNumber: 1,
            duration: 185, // 3:05
            artistName: "Test Artist",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.formattedDuration, "3:05")
    }

    func test_formattedDuration_withLongDuration_formatsCorrectly() {
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "Test Track",
            trackNumber: 1,
            duration: 3661, // 61:01
            artistName: "Test Artist",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.formattedDuration, "61:01")
    }

    func test_formattedDuration_withZeroDuration_formatsAsZero() {
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "Test Track",
            trackNumber: 1,
            duration: 0,
            artistName: "Test Artist",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.formattedDuration, "0:00")
    }

    func test_formattedDuration_withSecondsUnderTen_padsWithZero() {
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "Test Track",
            trackNumber: 1,
            duration: 125, // 2:05
            artistName: "Test Artist",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.formattedDuration, "2:05")
    }

    // MARK: - displayTitle Tests

    func test_displayTitle_includesTrackNumberAndTitle() {
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "Come Together",
            trackNumber: 1,
            duration: 259,
            artistName: "The Beatles",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.displayTitle, "1. Come Together")
    }

    func test_displayTitle_withDoubleDigitTrackNumber_formatsCorrectly() {
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "The End",
            trackNumber: 17,
            duration: 143,
            artistName: "The Beatles",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.displayTitle, "17. The End")
    }

    // MARK: - Identifiable Tests

    func test_id_matchesPlexID() {
        let track = Track(
            plexID: "54321",
            albumID: "100",
            title: "Test Track",
            trackNumber: 1,
            duration: 180,
            artistName: "Test Artist",
            key: "/library/metadata/1",
            thumbURL: nil
        )

        XCTAssertEqual(track.id, "54321")
    }

    // MARK: - Codable Tests

    func test_codable_encodesAndDecodesCorrectly() throws {
        let original = Track(
            plexID: "456",
            albumID: "789",
            title: "Here Comes The Sun",
            trackNumber: 7,
            duration: 185,
            artistName: "The Beatles",
            key: "/library/metadata/456",
            thumbURL: "https://example.com/track-thumb.jpg"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: encoded)

        XCTAssertEqual(decoded.plexID, original.plexID)
        XCTAssertEqual(decoded.albumID, original.albumID)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.trackNumber, original.trackNumber)
        XCTAssertEqual(decoded.duration, original.duration)
        XCTAssertEqual(decoded.artistName, original.artistName)
        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.thumbURL, original.thumbURL)
    }
}
