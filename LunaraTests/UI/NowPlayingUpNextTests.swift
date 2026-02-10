import Foundation
import Testing
@testable import Lunara

@MainActor
struct NowPlayingUpNextTests {
    @Test func upNextDropsPlayedTracks() {
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "4", title: "Four", index: 4, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        let upNext = NowPlayingUpNextBuilder.upNextTracks(
            tracks: tracks,
            currentRatingKey: "2"
        )

        #expect(upNext.map(\.ratingKey) == ["3", "4"])
    }

    @Test func upNextReturnsEmptyWhenCurrentMissing() {
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        let upNext = NowPlayingUpNextBuilder.upNextTracks(
            tracks: tracks,
            currentRatingKey: "missing"
        )

        #expect(upNext.isEmpty)
    }
}
