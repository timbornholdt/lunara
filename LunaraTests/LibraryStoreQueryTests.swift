import Foundation
import Testing
@testable import Lunara

struct LibraryStoreQueryTests {
    @Test
    func track_lookupReturnsTrackByID() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [makeAlbum(id: "album-1", title: "Album", artist: "Artist")],
                tracks: [
                    makeTrack(id: "track-1", albumID: "album-1", title: "Song 1", trackNumber: 1),
                    makeTrack(id: "track-2", albumID: "album-1", title: "Song 2", trackNumber: 2)
                ],
                artists: [],
                collections: []
            ),
            refreshedAt: Date(timeIntervalSince1970: 1000)
        )

        #expect(try await store.track(id: "track-2")?.title == "Song 2")
        #expect(try await store.track(id: "missing") == nil)
    }

    @Test
    func collection_lookupReturnsCollectionByID() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [],
                tracks: [],
                artists: [],
                collections: [
                    makeCollection(id: "collection-1", title: "Late Night"),
                    makeCollection(id: "collection-2", title: "Morning Coffee")
                ]
            ),
            refreshedAt: Date(timeIntervalSince1970: 1000)
        )

        #expect(try await store.collection(id: "collection-1")?.title == "Late Night")
        #expect(try await store.collection(id: "missing") == nil)
    }

    @Test
    func searchAlbums_matchesTitleAndArtist_caseAndDiacriticInsensitive_sortedByArtistThenTitle() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [
                    makeAlbum(id: "album-zeta", title: "Zeta", artist: "Beyoncé"),
                    makeAlbum(id: "album-lemonade", title: "Lemonade", artist: "Beyoncé"),
                    makeAlbum(id: "album-random", title: "Random Access Memories", artist: "Daft Punk")
                ],
                tracks: [],
                artists: [],
                collections: []
            ),
            refreshedAt: Date(timeIntervalSince1970: 1000)
        )

        let titleMatches = try await store.searchAlbums(query: "LEMONADE")
        let artistMatches = try await store.searchAlbums(query: "beyonce")

        #expect(titleMatches.map(\.plexID) == ["album-lemonade"])
        #expect(artistMatches.map(\.plexID) == ["album-lemonade", "album-zeta"])
    }

    @Test
    func searchArtists_matchesNameAndSortName_caseAndDiacriticInsensitive_sortedBySortNameThenName() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [],
                tracks: [],
                artists: [
                    makeArtist(id: "artist-bjork-post", name: "Björk Post", sortName: "Bjork Post"),
                    makeArtist(id: "artist-bjork", name: "Björk", sortName: "Bjork"),
                    makeArtist(id: "artist-daft", name: "Daft Punk", sortName: "Daft Punk")
                ],
                collections: []
            ),
            refreshedAt: Date(timeIntervalSince1970: 1000)
        )

        let nameMatches = try await store.searchArtists(query: "BJORK")
        let sortNameMatches = try await store.searchArtists(query: "bjork post")

        #expect(nameMatches.map(\.plexID) == ["artist-bjork", "artist-bjork-post"])
        #expect(sortNameMatches.map(\.plexID) == ["artist-bjork-post"])
    }

    @Test
    func searchCollections_matchesTitle_caseAndDiacriticInsensitive_sortedByTitle() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [],
                tracks: [],
                artists: [],
                collections: [
                    makeCollection(id: "collection-sigur", title: "Sigur Rós Essentials"),
                    makeCollection(id: "collection-z", title: "Zzz Sleep"),
                    makeCollection(id: "collection-a", title: "Ambient Mornings")
                ]
            ),
            refreshedAt: Date(timeIntervalSince1970: 1000)
        )

        let matches = try await store.searchCollections(query: "SIGUR ROS")
        let allCollections = try await store.searchCollections(query: "")

        #expect(matches.map(\.plexID) == ["collection-sigur"])
        #expect(allCollections.map(\.plexID) == ["collection-a", "collection-sigur", "collection-z"])
    }

    private func makeAlbum(id: String, title: String, artist: String) -> Album {
        Album(
            plexID: id,
            title: title,
            artistName: artist,
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String, title: String, trackNumber: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: title,
            trackNumber: trackNumber,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }

    private func makeArtist(id: String, name: String, sortName: String) -> Artist {
        Artist(
            plexID: id,
            name: name,
            sortName: sortName,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 1
        )
    }

    private func makeCollection(id: String, title: String) -> Collection {
        Collection(
            plexID: id,
            title: title,
            thumbURL: nil,
            summary: nil,
            albumCount: 1,
            updatedAt: nil
        )
    }
}
