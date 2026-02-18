import Testing
@testable import Lunara

struct AlbumTrackPresentationTests {
    @Test
    func secondaryArtist_returnsNil_whenTrackArtistMatchesAlbumArtist() {
        let value = AlbumTrackPresentation.secondaryArtist(
            trackArtist: "Adele",
            albumArtist: "adele"
        )

        #expect(value == nil)
    }

    @Test
    func secondaryArtist_returnsTrackArtist_whenTrackArtistDiffers() {
        let value = AlbumTrackPresentation.secondaryArtist(
            trackArtist: "Aimee Mann",
            albumArtist: "Various Artists"
        )

        #expect(value == "Aimee Mann")
    }

    @Test
    func secondaryArtist_returnsNil_whenTrackArtistIsEmpty() {
        let value = AlbumTrackPresentation.secondaryArtist(
            trackArtist: "   ",
            albumArtist: "Various Artists"
        )

        #expect(value == nil)
    }

    @Test
    func albumDuration_formatsWithoutHours_forShortDurations() {
        let value = AlbumTrackPresentation.albumDuration(2_143)

        #expect(value == "35:43")
    }

    @Test
    func albumDuration_formatsWithHours_forLongDurations() {
        let value = AlbumTrackPresentation.albumDuration(9_336)

        #expect(value == "2:35:36")
    }
}
