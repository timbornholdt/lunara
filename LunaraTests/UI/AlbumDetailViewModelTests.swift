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
            tracks: [PlexTrack(ratingKey: "1", title: "Track", index: 1, parentRatingKey: "10", duration: nil)]
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
}
