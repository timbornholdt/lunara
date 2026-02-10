import Foundation
import Testing
@testable import Lunara

@MainActor
struct TrackArtistDisplayTests {
    @Test func hidesArtistWhenMatchesAlbumArtist() {
        let track = PlexTrack(
            ratingKey: "1",
            title: "One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "10",
            duration: 1000,
            media: nil,
            originalTitle: "The Artist",
            grandparentTitle: "The Artist"
        )

        let display = TrackArtistDisplayResolver.displayArtist(
            for: track,
            albumArtist: "The Artist"
        )

        #expect(display == nil)
    }

    @Test func showsArtistWhenDifferent() {
        let track = PlexTrack(
            ratingKey: "1",
            title: "One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "10",
            duration: 1000,
            media: nil,
            originalTitle: "Guest Artist",
            grandparentTitle: "Album Artist"
        )

        let display = TrackArtistDisplayResolver.displayArtist(
            for: track,
            albumArtist: "Album Artist"
        )

        #expect(display == "Guest Artist")
    }
}
