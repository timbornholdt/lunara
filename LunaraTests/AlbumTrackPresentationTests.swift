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
}
