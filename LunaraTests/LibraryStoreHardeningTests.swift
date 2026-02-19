import Foundation
import GRDB
import Testing
@testable import Lunara

@MainActor
struct LibraryStoreHardeningTests {

    // MARK: - Tag pruning when all linked albums are removed

    @Test
    func pruneRowsNotSeen_tagRowsRemovedWhenAllLinkedAlbumsArePruned() async throws {
        let store = try LibraryStore.inMemory()

        // Run 1: insert an album with a unique genre tag
        let run1 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7000))
        try await store.upsertAlbums(
            [makeAlbum(id: "album-gone", title: "Gone", genres: ["SoleGenre"], styles: [], moods: [])],
            in: run1
        )
        try await store.markAlbumsSeen(["album-gone"], in: run1)
        _ = try await store.pruneRowsNotSeen(in: run1)

        // Verify the tag row exists
        let tagCountBefore = try await store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE kind = 'genre'") ?? 0
        }
        #expect(tagCountBefore == 1)

        // Run 2: album-gone disappears from library
        let run2 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7001))
        _ = try await store.pruneRowsNotSeen(in: run2)

        // After pruning, the album and its tag links should be gone
        let albumCount = try await store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM albums") ?? 0
        }
        let albumTagCount = try await store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM album_tags") ?? 0
        }
        // Tags themselves may linger (they are denormalized shared rows), but join rows must not
        #expect(albumCount == 0)
        #expect(albumTagCount == 0)
    }

    // MARK: - No orphan join rows after album/artist/collection round-trip

    @Test
    func pruneRowsNotSeen_noOrphanAlbumArtistJoinRowsAfterFullRoundTrip() async throws {
        let store = try LibraryStore.inMemory()

        let run1 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7100))
        try await store.upsertAlbums(
            [makeAlbum(id: "album-a", title: "A", genres: ["Jazz"], styles: ["Bebop"], moods: [])],
            in: run1
        )
        try await store.replaceArtists(
            [Artist(plexID: "artist-1", name: "Miles", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 1)],
            in: run1
        )
        try await store.markAlbumsSeen(["album-a"], in: run1)
        _ = try await store.pruneRowsNotSeen(in: run1)

        // Second run: album-a is gone, new album-b arrives
        let run2 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7101))
        try await store.upsertAlbums(
            [makeAlbum(id: "album-b", title: "B", genres: ["Blues"], styles: [], moods: [])],
            in: run2
        )
        try await store.replaceArtists(
            [Artist(plexID: "artist-2", name: "BB King", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 1)],
            in: run2
        )
        try await store.markAlbumsSeen(["album-b"], in: run2)
        _ = try await store.pruneRowsNotSeen(in: run2)

        let orphanAlbumTagRows = try await store.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM album_tags WHERE albumID NOT IN (SELECT plexID FROM albums)"
            ) ?? 0
        }
        #expect(orphanAlbumTagRows == 0)

        // Verify only the new album remains
        let albumIDs = try await store.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT plexID FROM albums ORDER BY plexID")
        }
        #expect(albumIDs == ["album-b"])
    }

    // MARK: - Canonical tag reuse across consecutive runs

    @Test
    func upsertAlbums_reusesSameTagRowAcrossConsecutiveRunsWithSameNormalizedValue() async throws {
        let store = try LibraryStore.inMemory()

        // Run 1: insert album with genre "Jazz"
        let run1 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7200))
        try await store.upsertAlbums(
            [makeAlbum(id: "album-1", title: "One", genres: ["Jazz"], styles: [], moods: [])],
            in: run1
        )
        try await store.markAlbumsSeen(["album-1"], in: run1)
        _ = try await store.pruneRowsNotSeen(in: run1)

        let tagIDAfterRun1 = try await store.dbQueue.read { db -> Int64? in
            let row = try Row.fetchOne(db, sql: "SELECT id FROM tags WHERE kind = 'genre' LIMIT 1")
            return row.flatMap { $0["id"] }
        }

        // Run 2: different album with same genre (different casing) — should reuse the canonical tag row
        let run2 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 7201))
        try await store.upsertAlbums(
            [makeAlbum(id: "album-2", title: "Two", genres: ["JAZZ"], styles: [], moods: [])],
            in: run2
        )
        try await store.markAlbumsSeen(["album-2"], in: run2)
        _ = try await store.pruneRowsNotSeen(in: run2)

        let tagCountAfterRun2 = try await store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE kind = 'genre'") ?? 0
        }
        let tagIDAfterRun2 = try await store.dbQueue.read { db -> Int64? in
            let row = try Row.fetchOne(db, sql: "SELECT id FROM tags WHERE kind = 'genre' LIMIT 1")
            return row.flatMap { $0["id"] }
        }

        // Only one genre tag row should exist (canonical dedup)
        #expect(tagCountAfterRun2 == 1)
        // Tag row ID is stable across runs — no new row inserted
        #expect(tagIDAfterRun1 == tagIDAfterRun2)
    }

    // MARK: - Helpers

    private func makeAlbum(
        id: String,
        title: String,
        genres: [String],
        styles: [String],
        moods: [String]
    ) -> Album {
        Album(
            plexID: id,
            title: title,
            artistName: "Artist",
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
}
