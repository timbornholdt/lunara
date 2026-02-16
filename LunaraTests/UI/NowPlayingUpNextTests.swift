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

    @Test func upNextItemsLimitReturnsExactlyLimitItems() {
        let tracks = (0..<5000).map { i in
            PlexTrack(ratingKey: "\(i)", title: "Track \(i)", index: i, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        }

        let items = NowPlayingUpNextBuilder.upNextItems(tracks: tracks, currentIndex: 0, limit: 50)

        #expect(items.count == 50)
    }

    @Test func upNextItemsLimitReturnsAllWhenUnderLimit() {
        let tracks = (0..<11).map { i in
            PlexTrack(ratingKey: "\(i)", title: "Track \(i)", index: i, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        }

        let items = NowPlayingUpNextBuilder.upNextItems(tracks: tracks, currentIndex: 0, limit: 50)

        #expect(items.count == 10)
    }

    @Test func remainingCountComputesCorrectly() {
        let tracks = (0..<5000).map { i in
            PlexTrack(ratingKey: "\(i)", title: "Track \(i)", index: i, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        }

        let remaining = NowPlayingUpNextBuilder.remainingCount(tracks: tracks, currentIndex: 0, limit: 50)

        #expect(remaining == 4949)
    }

    @Test func remainingCountIsZeroWhenUnderLimit() {
        let tracks = (0..<11).map { i in
            PlexTrack(ratingKey: "\(i)", title: "Track \(i)", index: i, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        }

        let remaining = NowPlayingUpNextBuilder.remainingCount(tracks: tracks, currentIndex: 0, limit: 50)

        #expect(remaining == 0)
    }
}
