import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryViewModelTests {
    @Test func loadsSectionsSelectsStoredSectionAndLoadsAlbums() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: "2")
        let service = StubLibraryService(
            sections: [
                PlexLibrarySection(key: "1", title: "Video", type: "movie"),
                PlexLibrarySection(key: "2", title: "Music", type: "artist")
            ],
            albums: [
                PlexAlbum(
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
            ],
            tracks: []
        )
        var invalidated = false
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true }
        )

        await viewModel.loadSections()

        #expect(viewModel.sections.count == 1)
        #expect(viewModel.selectedSection?.key == "2")
        #expect(viewModel.albums.count == 1)
        #expect(selectionStore.key == "2")
        #expect(invalidated == false)
    }

    @Test func selectingSectionLoadsAlbums() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: nil)
        let service = StubLibraryService(
            sections: [
                PlexLibrarySection(key: "1", title: "Music", type: "artist"),
                PlexLibrarySection(key: "2", title: "More", type: "music")
            ],
            albums: [
                PlexAlbum(
                    ratingKey: "99",
                    title: "Alt",
                    thumb: nil,
                    art: nil,
                    year: 2020,
                    artist: nil,
                    summary: nil,
                    genres: nil,
                    styles: nil,
                    moods: nil,
                    rating: nil,
                    userRating: nil,
                    key: nil
                )
            ],
            tracks: []
        )
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: {}
        )

        await viewModel.selectSection(PlexLibrarySection(key: "2", title: "More", type: "music"))

        #expect(viewModel.selectedSection?.key == "2")
        #expect(viewModel.albums.first?.ratingKey == "99")
        #expect(selectionStore.key == "2")
    }

    @Test func unauthorizedClearsTokenAndInvalidatesSession() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: nil)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            error: PlexHTTPError.httpStatus(401, Data())
        )
        var invalidated = false
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true }
        )

        await viewModel.loadSections()

        #expect(tokenStore.token == nil)
        #expect(invalidated == true)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
    }
}
