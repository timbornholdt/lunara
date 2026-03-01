import Foundation
import GRDB
import Testing
@testable import Lunara

@MainActor
struct LibraryStoreRelationshipReconciliationTests {
    @Test
    func replaceArtists_prunesRowsNotSeenInLaterRun() async throws {
        let store = try LibraryStore.inMemory()
        let firstRun = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5310))

        try await store.replaceArtists(
            [
                Artist(plexID: "artist-old", name: "Old", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 1)
            ],
            in: firstRun
        )
        _ = try await store.pruneRowsNotSeen(in: firstRun)

        let secondRun = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5311))
        try await store.replaceArtists(
            [
                Artist(plexID: "artist-new", name: "New", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 2)
            ],
            in: secondRun
        )
        _ = try await store.pruneRowsNotSeen(in: secondRun)

        let artists = try await store.fetchArtists()
        #expect(artists.map(\.plexID) == ["artist-new"])
    }

    @Test
    func replaceCollections_prunesRowsNotSeenInLaterRun() async throws {
        let store = try LibraryStore.inMemory()
        let firstRun = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5312))

        try await store.replaceCollections(
            [
                Collection(plexID: "collection-old", title: "Old", thumbURL: nil, summary: nil, albumCount: 1, updatedAt: nil)
            ],
            in: firstRun
        )
        _ = try await store.pruneRowsNotSeen(in: firstRun)

        let secondRun = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5313))
        try await store.replaceCollections(
            [
                Collection(plexID: "collection-new", title: "New", thumbURL: nil, summary: nil, albumCount: 2, updatedAt: nil)
            ],
            in: secondRun
        )
        _ = try await store.pruneRowsNotSeen(in: secondRun)

        let collections = try await store.fetchCollections()
        #expect(collections.map(\.plexID) == ["collection-new"])
    }

    @Test
    func upsertAlbums_canonicalizesTagCollisionsByKindAndNormalizedValue() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 6000))

        try await store.upsertAlbums(
            [
                makeAlbum(id: "album-1", title: "One", genres: ["Beyonce"], styles: ["Nu Jazz"], moods: ["Calm"]),
                makeAlbum(id: "album-2", title: "Two", genres: ["BEYONCE"], styles: ["NÚ JAZZ"], moods: ["calm"])
            ],
            in: run
        )

        let tagRows: [Row] = try await store.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT kind, normalizedName FROM tags ORDER BY kind, normalizedName"
            )
        }

        let keys = tagRows.map { row in
            let kind: String = row["kind"]
            let normalizedName: String = row["normalizedName"]
            return "\(kind):\(normalizedName)"
        }

        let expected = [
            "genre:\(LibraryStoreSearchNormalizer.normalize("Beyonce"))",
            "mood:\(LibraryStoreSearchNormalizer.normalize("Calm"))",
            "style:\(LibraryStoreSearchNormalizer.normalize("Nu Jazz"))"
        ].sorted()
        #expect(keys == expected)
    }

    @Test
    func pruneRowsNotSeen_prunesPlaylistRowsAndRelationshipRowsDeterministically() async throws {
        let store = try LibraryStore.inMemory()

        let firstRun = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 6100))
        let oldAlbum = makeAlbum(id: "album-old", title: "Old", genres: ["Space"], styles: [], moods: [])
        let oldTrack = makeTrack(id: "track-old", albumID: "album-old", number: 1)
        try await store.upsertAlbums([oldAlbum], in: firstRun)
        try await store.upsertTracks([oldTrack], in: firstRun)
        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "playlist-1", title: "Playlist", trackCount: 2, updatedAt: nil, thumbURL: nil)],
            in: firstRun
        )
        try await store.upsertPlaylistItems(
            [
                LibraryPlaylistItemSnapshot(trackID: "track-old", position: 0, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "track-missing", position: 1, playlistItemID: nil)
            ],
            playlistID: "playlist-1",
            in: firstRun
        )
        try await store.markAlbumsSeen([oldAlbum.plexID], in: firstRun)
        try await store.markTracksSeen([oldTrack.plexID], in: firstRun)
        _ = try await store.pruneRowsNotSeen(in: firstRun)

        let secondRun = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 6200))
        let newAlbum = makeAlbum(id: "album-new", title: "New", genres: ["SPACE"], styles: [], moods: [])
        let newTrack = makeTrack(id: "track-new", albumID: "album-new", number: 1)
        try await store.upsertAlbums([newAlbum], in: secondRun)
        try await store.upsertTracks([newTrack], in: secondRun)
        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "playlist-1", title: "Playlist Updated", trackCount: 1, updatedAt: nil, thumbURL: nil)],
            in: secondRun
        )
        try await store.upsertPlaylistItems(
            [LibraryPlaylistItemSnapshot(trackID: "track-new", position: 0, playlistItemID: nil)],
            playlistID: "playlist-1",
            in: secondRun
        )
        try await store.markAlbumsSeen([newAlbum.plexID], in: secondRun)
        try await store.markTracksSeen([newTrack.plexID], in: secondRun)
        _ = try await store.pruneRowsNotSeen(in: secondRun)

        let orphanCounts = try await store.dbQueue.read { db in
            let albumTagOrphans = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM album_tags
                WHERE albumID NOT IN (SELECT plexID FROM albums)
                   OR tagID NOT IN (SELECT id FROM tags)
                """
            ) ?? 0
            let playlistItemOrphans = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM playlist_items WHERE playlistID NOT IN (SELECT plexID FROM playlists)"
            ) ?? 0
            let playlistRows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlists") ?? 0
            let playlistItems = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlist_items") ?? 0
            return (albumTagOrphans, playlistItemOrphans, playlistRows, playlistItems)
        }

        #expect(orphanCounts.0 == 0)
        #expect(orphanCounts.1 == 0)
        #expect(orphanCounts.2 == 1)
        #expect(orphanCounts.3 == 1)
    }

    private func makeAlbum(
        id: String,
        title: String,
        artist: String = "Artist",
        genres: [String],
        styles: [String],
        moods: [String]
    ) -> Album {
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
            duration: 0,
            genres: genres,
            styles: styles,
            moods: moods
        )
    }

    private func makeTrack(id: String, albumID: String, number: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: number,
            duration: 100,
            artistName: "Artist",
            key: "/library/parts/\(id)/1/file.mp3",
            thumbURL: nil
        )
    }
}
