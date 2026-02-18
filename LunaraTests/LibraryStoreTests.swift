import Foundation
import Testing
@testable import Lunara

struct LibraryStoreTests {
    @Test
    func fetchesEmptyCollectionsFromFreshStore() async throws {
        let store = try LibraryStore.inMemory()

        let albums = try await store.fetchAlbums(page: LibraryPage(number: 1, size: 20))
        let artists = try await store.fetchArtists()
        let collections = try await store.fetchCollections()
        let lastRefresh = try await store.lastRefreshDate()

        #expect(albums.isEmpty)
        #expect(artists.isEmpty)
        #expect(collections.isEmpty)
        #expect(lastRefresh == nil)
    }

    @Test
    func replaceLibrary_persistsAndPaginatesAlbums() async throws {
        let store = try LibraryStore.inMemory()

        let snapshot = LibrarySnapshot(
            albums: [
                makeAlbum(id: "album-c", title: "Gamma", artist: "Artist C"),
                makeAlbum(id: "album-a", title: "Alpha", artist: "Artist A"),
                makeAlbum(id: "album-b", title: "Beta", artist: "Artist B")
            ],
            tracks: [],
            artists: [],
            collections: []
        )

        try await store.replaceLibrary(with: snapshot, refreshedAt: Date(timeIntervalSince1970: 1000))

        let firstPage = try await store.fetchAlbums(page: LibraryPage(number: 1, size: 2))
        let secondPage = try await store.fetchAlbums(page: LibraryPage(number: 2, size: 2))

        #expect(firstPage.map(\.plexID) == ["album-a", "album-b"])
        #expect(secondPage.map(\.plexID) == ["album-c"])
    }

    @Test
    func replaceLibrary_replacesExistingRowsAndRefreshTimestamp() async throws {
        let store = try LibraryStore.inMemory()

        let firstSnapshot = LibrarySnapshot(
            albums: [makeAlbum(id: "old-album", title: "Old", artist: "Artist")],
            tracks: [makeTrack(id: "old-track", albumID: "old-album", trackNumber: 1)],
            artists: [makeArtist(id: "old-artist", name: "Old Artist")],
            collections: [makeCollection(id: "old-collection", title: "Old Collection")]
        )
        try await store.replaceLibrary(with: firstSnapshot, refreshedAt: Date(timeIntervalSince1970: 2000))

        let secondSnapshot = LibrarySnapshot(
            albums: [makeAlbum(id: "new-album", title: "New", artist: "Artist")],
            tracks: [makeTrack(id: "new-track", albumID: "new-album", trackNumber: 1)],
            artists: [makeArtist(id: "new-artist", name: "New Artist")],
            collections: [makeCollection(id: "new-collection", title: "New Collection")]
        )
        try await store.replaceLibrary(with: secondSnapshot, refreshedAt: Date(timeIntervalSince1970: 3000))

        #expect(try await store.fetchAlbum(id: "old-album") == nil)
        #expect(try await store.fetchAlbum(id: "new-album")?.plexID == "new-album")
        #expect(try await store.fetchTracks(forAlbum: "new-album").map(\.plexID) == ["new-track"])
        #expect(try await store.fetchArtists().map(\.plexID) == ["new-artist"])
        #expect(try await store.fetchCollections().map(\.plexID) == ["new-collection"])
        #expect(try await store.lastRefreshDate() == Date(timeIntervalSince1970: 3000))
    }

    @Test
    func fetchTracks_forAlbum_returnsOnlyAlbumTracksSortedByTrackNumber() async throws {
        let store = try LibraryStore.inMemory()

        let snapshot = LibrarySnapshot(
            albums: [
                makeAlbum(id: "album-a", title: "A", artist: "Artist"),
                makeAlbum(id: "album-b", title: "B", artist: "Artist")
            ],
            tracks: [
                makeTrack(id: "track-2", albumID: "album-a", trackNumber: 2),
                makeTrack(id: "track-1", albumID: "album-a", trackNumber: 1),
                makeTrack(id: "track-b", albumID: "album-b", trackNumber: 1)
            ],
            artists: [],
            collections: []
        )

        try await store.replaceLibrary(with: snapshot, refreshedAt: Date())

        let albumATracks = try await store.fetchTracks(forAlbum: "album-a")

        #expect(albumATracks.map(\.plexID) == ["track-1", "track-2"])
    }

    @Test
    func artworkPath_roundTripsAndDeletesByCompositeKey() async throws {
        let store = try LibraryStore.inMemory()
        let key = ArtworkKey(ownerID: "album-1", ownerType: .album, variant: .thumbnail)

        try await store.setArtworkPath("/tmp/first.jpg", for: key)
        #expect(try await store.artworkPath(for: key) == "/tmp/first.jpg")

        try await store.setArtworkPath("/tmp/updated.jpg", for: key)
        #expect(try await store.artworkPath(for: key) == "/tmp/updated.jpg")

        try await store.deleteArtworkPath(for: key)
        #expect(try await store.artworkPath(for: key) == nil)
    }

    @Test
    func replaceLibrary_withRealPlexCapture_persistsSampleSnapshot() async throws {
        let store = try LibraryStore.inMemory()
        let snapshot = try fixtureSnapshot()

        try await store.replaceLibrary(with: snapshot, refreshedAt: Date(timeIntervalSince1970: 4000))

        #expect(!snapshot.isEmpty)
        #expect(!(try await store.fetchAlbums(page: LibraryPage(number: 1, size: 25))).isEmpty)
        #expect(!(try await store.fetchArtists()).isEmpty)
        #expect(!(try await store.fetchCollections()).isEmpty)

        let sampleAlbumID = try #require(snapshot.albums.first?.plexID)
        let tracks = try await store.fetchTracks(forAlbum: sampleAlbumID)
        #expect(!tracks.isEmpty)
    }

    private func fixtureSnapshot() throws -> LibrarySnapshot {
        let decoder = XMLDecoder()

        let albumsContainer = try decoder.decode(PlexMediaContainer.self, from: try fixtureData(name: "album_metadata.xml"))
        let tracksContainer = try decoder.decode(PlexMediaContainer.self, from: try fixtureData(name: "album_children.xml"))
        let collectionsContainer = try decoder.decode(PlexMediaContainer.self, from: try fixtureData(name: "plex-collections-sample.xml"))

        let albums = (albumsContainer.directories ?? []).compactMap { directory -> Album? in
            guard directory.type == "album", let albumID = directory.ratingKey, !albumID.isEmpty else { return nil }
            return Album(
                plexID: albumID,
                title: directory.title,
                artistName: directory.parentTitle ?? "Unknown Artist",
                year: directory.year,
                thumbURL: directory.thumb,
                genre: directory.genre,
                rating: directory.rating.map(Int.init),
                addedAt: directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                trackCount: directory.leafCount ?? 0,
                duration: directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0
            )
        }

        let tracks = (tracksContainer.metadata ?? []).compactMap { metadata -> Track? in
            guard metadata.type == "track" else { return nil }
            guard let albumID = metadata.parentRatingKey, !albumID.isEmpty else { return nil }
            guard let key = metadata.key, !key.isEmpty else { return nil }
            return Track(
                plexID: metadata.ratingKey,
                albumID: albumID,
                title: metadata.title,
                trackNumber: metadata.index ?? 0,
                duration: TimeInterval(metadata.duration ?? 0) / 1000.0,
                artistName: metadata.grandparentTitle ?? metadata.parentTitle ?? "Unknown Artist",
                key: key,
                thumbURL: metadata.thumb
            )
        }

        let artists = (albumsContainer.directories ?? []).compactMap { directory -> Artist? in
            guard directory.type == "album" else { return nil }
            guard let artistID = directory.parentRatingKey, !artistID.isEmpty else { return nil }
            guard let artistName = directory.parentTitle, !artistName.isEmpty else { return nil }

            return Artist(
                plexID: artistID,
                name: artistName,
                sortName: nil,
                thumbURL: nil,
                genre: directory.genre,
                summary: nil,
                albumCount: 0
            )
        }

        let collections = (collectionsContainer.directories ?? []).compactMap { directory -> Collection? in
            guard directory.type == "collection", let collectionID = directory.ratingKey, !collectionID.isEmpty else { return nil }
            return Collection(
                plexID: collectionID,
                title: directory.title,
                thumbURL: directory.thumb,
                summary: directory.summary,
                albumCount: 0,
                updatedAt: nil
            )
        }

        return LibrarySnapshot(albums: albums, tracks: tracks, artists: artists, collections: collections)
    }

    private func fixtureData(name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root
            .appendingPathComponent("tmp")
            .appendingPathComponent("plex-capture")
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
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

    private func makeTrack(id: String, albumID: String, trackNumber: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: trackNumber,
            duration: 100,
            artistName: "Artist",
            key: "/library/parts/\(id)/1/file.mp3",
            thumbURL: nil
        )
    }

    private func makeArtist(id: String, name: String) -> Artist {
        Artist(
            plexID: id,
            name: name,
            sortName: nil,
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
