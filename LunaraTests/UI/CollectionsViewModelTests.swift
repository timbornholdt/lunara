import Foundation
import Testing
@testable import Lunara

@MainActor
struct CollectionsViewModelTests {
    @Test func loadsCollectionsFromFirstMusicSectionAndLogsTitles() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [
            PlexLibrarySection(key: "1", title: "Movies", type: "movie"),
            PlexLibrarySection(key: "2", title: "Music", type: "artist")
        ]
        let collections = [
            PlexCollection(ratingKey: "100", title: "Zed", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "101", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        ]
        let service = RecordingLibraryService(
            sections: sections,
            collections: collections
        )
        var loggedTitles: [String] = []
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            logger: { loggedTitles = $0 }
        )

        await viewModel.loadCollections()

        #expect(service.lastCollectionsSectionId == "2")
        #expect(viewModel.collections.count == 2)
        #expect(loggedTitles == ["Zed", "Current Vibes"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func ordersPinnedCollectionsFirstThenAlphabetical() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "2", title: "Music", type: "artist")]
        let collections = [
            PlexCollection(ratingKey: "1", title: "Zed", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "2", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "3", title: "Alpha", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "4", title: "The Key Albums", thumb: nil, art: nil, updatedAt: nil, key: nil)
        ]
        let service = RecordingLibraryService(sections: sections, collections: collections)
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service }
        )

        await viewModel.loadCollections()

        #expect(viewModel.collections.map(\.title) == [
            "Current Vibes",
            "The Key Albums",
            "Alpha",
            "Zed"
        ])
    }

    @Test func identifiesPinnedCollections() {
        let viewModel = CollectionsViewModel(
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in RecordingLibraryService(sections: [], collections: []) }
        )
        let pinned = PlexCollection(ratingKey: "1", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let normal = PlexCollection(ratingKey: "2", title: "Other", thumb: nil, art: nil, updatedAt: nil, key: nil)

        #expect(viewModel.isPinned(pinned))
        #expect(viewModel.isPinned(normal) == false)
    }

    @Test func noMusicSectionSetsError() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "1", title: "Movies", type: "movie")]
        let service = RecordingLibraryService(sections: sections, collections: [])
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service }
        )

        await viewModel.loadCollections()

        #expect(viewModel.collections.isEmpty)
        #expect(viewModel.errorMessage == "No music library found.")
    }
}

@MainActor
struct CollectionAlbumsViewModelTests {
    @Test func loadsAlbumsForCollectionAndDedupes() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "2", title: "Music", type: "artist")]
        let albumA = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
            librarySectionID: 1,
            parentRatingKey: nil,
            studio: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let albumB = PlexAlbum(
            ratingKey: "11",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
            librarySectionID: 1,
            parentRatingKey: nil,
            studio: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let service = RecordingLibraryService(
            sections: sections,
            collections: [],
            albumsByCollectionKey: ["999": [albumA, albumB]]
        )
        let viewModel = CollectionAlbumsViewModel(
            collection: PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil),
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service }
        )

        await viewModel.loadAlbums()

        #expect(viewModel.albums.count == 1)
        #expect(viewModel.ratingKeys(for: albumA).sorted() == ["10", "11"])
        #expect(service.lastCollectionItemsSectionId == "2")
        #expect(service.lastCollectionItemsKey == "999")
    }
}

@MainActor
final class RecordingLibraryService: PlexLibraryServicing {
    private let sections: [PlexLibrarySection]
    private let collections: [PlexCollection]
    private let albumsByCollectionKey: [String: [PlexAlbum]]
    private let albums: [PlexAlbum]
    private let error: Error?

    private(set) var lastCollectionsSectionId: String?
    private(set) var lastCollectionItemsSectionId: String?
    private(set) var lastCollectionItemsKey: String?

    init(
        sections: [PlexLibrarySection],
        collections: [PlexCollection],
        albumsByCollectionKey: [String: [PlexAlbum]] = [:],
        albums: [PlexAlbum] = [],
        error: Error? = nil
    ) {
        self.sections = sections
        self.collections = collections
        self.albumsByCollectionKey = albumsByCollectionKey
        self.albums = albums
        self.error = error
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        if let error { throw error }
        return sections
    }

    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        return albums
    }

    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack] {
        if let error { throw error }
        return []
    }

    func fetchCollections(sectionId: String) async throws -> [PlexCollection] {
        if let error { throw error }
        lastCollectionsSectionId = sectionId
        return collections
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        lastCollectionItemsSectionId = sectionId
        lastCollectionItemsKey = collectionKey
        return albumsByCollectionKey[collectionKey] ?? []
    }
}
