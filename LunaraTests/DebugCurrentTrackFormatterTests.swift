import Testing
@testable import Lunara

struct DebugCurrentTrackFormatterTests {
    @Test
    func label_withoutTrackID_returnsNone() {
        let label = DebugCurrentTrackFormatter.label(for: nil, tracksByID: [:])

        #expect(label == "none")
    }

    @Test
    func label_withUnknownTrackID_returnsTrackID() {
        let label = DebugCurrentTrackFormatter.label(for: "track-42", tracksByID: [:])

        #expect(label == "track-42")
    }

    @Test
    func label_withKnownTrack_returnsArtistTitleAndTrackID() {
        let track = Track(
            plexID: "track-99",
            albumID: "album-1",
            title: "Song Title",
            trackNumber: 1,
            duration: 120,
            artistName: "Artist Name",
            key: "/library/metadata/99",
            thumbURL: nil
        )

        let label = DebugCurrentTrackFormatter.label(for: track.plexID, tracksByID: [track.plexID: track])

        #expect(label == "Artist Name - Song Title (track-99)")
    }
}
