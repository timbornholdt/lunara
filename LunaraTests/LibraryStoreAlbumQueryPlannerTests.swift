import Foundation
import GRDB
import Testing
@testable import Lunara

@MainActor
struct LibraryStoreAlbumQueryPlannerTests {
    @Test
    func queryAlbums_filtersByGenreMoodAndInclusiveYearRange() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7000))

        try await store.upsertAlbums(
            [
                Self.makeAlbum(id: "album-match", title: "Quiet Pulse", artist: "A", year: 1986, genres: ["Ambient"], moods: ["Calm"]),
                Self.makeAlbum(id: "album-old", title: "Pre Dawn", artist: "B", year: 1979, genres: ["Ambient"], moods: ["Calm"]),
                Self.makeAlbum(id: "album-wrong-mood", title: "Sky Drift", artist: "C", year: 1989, genres: ["Ambient"], moods: ["Driving"]),
                Self.makeAlbum(id: "album-wrong-genre", title: "Night Tide", artist: "D", year: 1991, genres: ["Drone"], moods: ["Calm"]),
                Self.makeAlbum(id: "album-no-year", title: "Untimed", artist: "E", year: nil, genres: ["Ambient"], moods: ["Calm"])
            ],
            in: run
        )

        let results = try await store.queryAlbums(
            filter: AlbumQueryFilter(
                yearRange: 1980 ... 1994,
                genreTags: ["ambient"],
                moodTags: ["calm"]
            )
        )

        #expect(results.map(\.plexID) == ["album-match"])
    }

    @Test
    func queryAlbums_appliesAllSemanticsWithinTagKind() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7100))

        try await store.upsertAlbums(
            [
                Self.makeAlbum(
                    id: "album-all",
                    title: "Dual Tone",
                    artist: "A",
                    year: 1990,
                    genres: ["Ambient", "Electronic"],
                    moods: ["Calm"]
                ),
                Self.makeAlbum(
                    id: "album-partial",
                    title: "Single Tone",
                    artist: "A",
                    year: 1990,
                    genres: ["Ambient"],
                    moods: ["Calm"]
                )
            ],
            in: run
        )

        let results = try await store.queryAlbums(
            filter: AlbumQueryFilter(
                genreTags: ["ambient", "electronic"],
                moodTags: ["calm"]
            )
        )

        #expect(results.map(\.plexID) == ["album-all"])
    }

    @Test
    func queryAlbums_appliesArtistAndCollectionConstraintsWithAllSemantics() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7200))

        try await store.upsertAlbums(
            [
                Self.makeAlbum(id: "album-all-relations", title: "Lines", artist: "Artist", year: 1993, genres: [], moods: []),
                Self.makeAlbum(id: "album-partial-relations", title: "Lines", artist: "Artist", year: 1992, genres: [], moods: [])
            ],
            in: run
        )
        try await store.replaceArtists(
            [
                Artist(plexID: "artist-a", name: "Artist A", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 1),
                Artist(plexID: "artist-b", name: "Artist B", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 1)
            ],
            in: run
        )
        try await store.replaceCollections(
            [
                Collection(plexID: "collection-a", title: "Collection A", thumbURL: nil, summary: nil, albumCount: 1, updatedAt: nil),
                Collection(plexID: "collection-b", title: "Collection B", thumbURL: nil, summary: nil, albumCount: 1, updatedAt: nil)
            ],
            in: run
        )

        try await store.dbQueue.write { db in
            try Self.insertArtistLink(albumID: "album-all-relations", artistID: "artist-a", run: run, db: db)
            try Self.insertArtistLink(albumID: "album-all-relations", artistID: "artist-b", run: run, db: db)
            try Self.insertArtistLink(albumID: "album-partial-relations", artistID: "artist-a", run: run, db: db)

            try Self.insertCollectionLink(albumID: "album-all-relations", collectionID: "collection-a", run: run, db: db)
            try Self.insertCollectionLink(albumID: "album-all-relations", collectionID: "collection-b", run: run, db: db)
            try Self.insertCollectionLink(albumID: "album-partial-relations", collectionID: "collection-a", run: run, db: db)
        }

        let results = try await store.queryAlbums(
            filter: AlbumQueryFilter(
                artistIDs: ["artist-a", "artist-b"],
                collectionIDs: ["collection-a", "collection-b"]
            )
        )

        #expect(results.map(\.plexID) == ["album-all-relations"])
    }

    @Test
    func queryAlbums_sortsDeterministicallyByArtistTitleThenPlexID() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7300))

        try await store.upsertAlbums(
            [
                Self.makeAlbum(id: "album-b", title: "Same", artist: "Artist", year: 1990, genres: [], moods: []),
                Self.makeAlbum(id: "album-a", title: "Same", artist: "Artist", year: 1990, genres: [], moods: []),
                Self.makeAlbum(id: "album-c", title: "Zed", artist: "Artist", year: 1990, genres: [], moods: [])
            ],
            in: run
        )

        let results = try await store.queryAlbums(filter: .all)
        #expect(results.map(\.plexID) == ["album-a", "album-b", "album-c"])
    }

    private nonisolated static func makeAlbum(
        id: String,
        title: String,
        artist: String,
        year: Int?,
        genres: [String],
        moods: [String]
    ) -> Album {
        Album(
            plexID: id,
            title: title,
            artistName: artist,
            year: year,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0,
            genres: genres,
            styles: [],
            moods: moods
        )
    }

    private nonisolated static func insertArtistLink(albumID: String, artistID: String, run: LibrarySyncRun, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO album_artists (albumID, artistID, lastSeenSyncID, lastSeenAt)
            VALUES (?, ?, ?, ?)
            """,
            arguments: [albumID, artistID, run.id, run.startedAt]
        )
    }

    private nonisolated static func insertCollectionLink(albumID: String, collectionID: String, run: LibrarySyncRun, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO album_collections (albumID, collectionID, lastSeenSyncID, lastSeenAt)
            VALUES (?, ?, ?, ?)
            """,
            arguments: [albumID, collectionID, run.id, run.startedAt]
        )
    }
}
