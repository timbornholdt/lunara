import Foundation
import Testing
@testable import Lunara

@MainActor
struct AlbumDetailViewModelTests {
    @Test func loadsTracksForAlbum() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [PlexTrack(ratingKey: "1", title: "Track", index: 1, parentRatingKey: "10", duration: nil, media: nil)]
        )
        var invalidated = false
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true }
        )

        await viewModel.loadTracks()

        #expect(viewModel.tracks.count == 1)
        #expect(invalidated == false)
    }

    @Test func unauthorizedClearsTokenAndInvalidatesSession() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            error: PlexHTTPError.httpStatus(401, Data())
        )
        var invalidated = false
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true }
        )

        await viewModel.loadTracks()

        #expect(tokenStore.token == nil)
        #expect(invalidated == true)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
    }

    @Test func playAlbumStartsAtFirstTrack() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let playback = StubPlaybackController()
        let viewModel = AlbumDetailViewModel(album: album, playbackController: playback)
        viewModel.tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentRatingKey: "10", duration: nil, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentRatingKey: "10", duration: nil, media: nil)
        ]

        viewModel.playAlbum()

        #expect(playback.lastStartIndex == 0)
        #expect(playback.lastTracks?.count == 2)
    }

    @Test func playTrackStartsAtSelectedIndex() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let playback = StubPlaybackController()
        let viewModel = AlbumDetailViewModel(album: album, playbackController: playback)
        let trackOne = PlexTrack(ratingKey: "1", title: "One", index: 1, parentRatingKey: "10", duration: nil, media: nil)
        let trackTwo = PlexTrack(ratingKey: "2", title: "Two", index: 2, parentRatingKey: "10", duration: nil, media: nil)
        viewModel.tracks = [trackOne, trackTwo]

        viewModel.playTrack(trackTwo)

        #expect(playback.lastStartIndex == 1)
    }
}

private final class StubPlaybackController: PlaybackControlling {
    private(set) var lastTracks: [PlexTrack]?
    private(set) var lastStartIndex: Int?

    func play(tracks: [PlexTrack], startIndex: Int) {
        lastTracks = tracks
        lastStartIndex = startIndex
    }

    func stop() {
    }
}
