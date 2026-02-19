import Foundation
import GRDB

extension LibraryStore {
    func beginIncrementalSync(startedAt: Date) async throws -> LibrarySyncRun {
        let run = LibrarySyncRun(startedAt: startedAt)

        try await dbQueue.write { db in
            try LibraryMetadataRecord(
                key: LibraryStoreMigrations.lastIncrementalRunIDMetadataKey,
                value: run.id
            ).save(db)
        }

        return run
    }

    func upsertTracks(_ tracks: [Track], in run: LibrarySyncRun) async throws {
        try await dbQueue.write { db in
            for track in tracks {
                try TrackRecord(model: track).save(db)
            }
        }
    }

    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws {
        guard !albumIDs.isEmpty else { return }

        try await dbQueue.write { db in
            _ = try AlbumRecord
                .filter(albumIDs.contains(Column("plexID")))
                .updateAll(
                    db,
                    [
                        Column("lastSeenSyncID").set(to: run.id),
                        Column("lastSeenAt").set(to: run.startedAt)
                    ]
                )
        }
    }

    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws {
        guard !trackIDs.isEmpty else { return }

        try await dbQueue.write { db in
            _ = try TrackRecord
                .filter(trackIDs.contains(Column("plexID")))
                .updateAll(
                    db,
                    [
                        Column("lastSeenSyncID").set(to: run.id),
                        Column("lastSeenAt").set(to: run.startedAt)
                    ]
                )
        }
    }

    func pruneRowsNotSeen(in run: LibrarySyncRun) async throws -> LibrarySyncPruneResult {
        try await dbQueue.write { db in
            let staleTrackIDs = try String.fetchAll(
                db,
                sql: "SELECT plexID FROM tracks WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?",
                arguments: [run.id]
            )
            let staleAlbumIDs = try String.fetchAll(
                db,
                sql: "SELECT plexID FROM albums WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?",
                arguments: [run.id]
            )
            let staleArtistIDs = try String.fetchAll(
                db,
                sql: "SELECT plexID FROM artists WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?",
                arguments: [run.id]
            )
            let staleCollectionIDs = try String.fetchAll(
                db,
                sql: "SELECT plexID FROM collections WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?",
                arguments: [run.id]
            )

            try db.execute(sql: "DELETE FROM playlist_items WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?", arguments: [run.id])
            try db.execute(sql: "DELETE FROM album_tags WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?", arguments: [run.id])
            try db.execute(sql: "DELETE FROM album_artists WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?", arguments: [run.id])
            try db.execute(sql: "DELETE FROM album_collections WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?", arguments: [run.id])
            try db.execute(sql: "DELETE FROM tags WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?", arguments: [run.id])
            try db.execute(sql: "DELETE FROM playlists WHERE lastSeenSyncID IS NULL OR lastSeenSyncID != ?", arguments: [run.id])

            if !staleTrackIDs.isEmpty {
                _ = try TrackRecord
                    .filter(staleTrackIDs.contains(Column("plexID")))
                    .deleteAll(db)
            }

            if !staleAlbumIDs.isEmpty {
                _ = try AlbumRecord
                    .filter(staleAlbumIDs.contains(Column("plexID")))
                    .deleteAll(db)
            }

            if !staleArtistIDs.isEmpty {
                _ = try ArtistRecord
                    .filter(staleArtistIDs.contains(Column("plexID")))
                    .deleteAll(db)
            }

            if !staleCollectionIDs.isEmpty {
                _ = try CollectionRecord
                    .filter(staleCollectionIDs.contains(Column("plexID")))
                    .deleteAll(db)
            }

            try db.execute(sql: "DELETE FROM album_tags WHERE albumID NOT IN (SELECT plexID FROM albums)")
            try db.execute(sql: "DELETE FROM album_tags WHERE tagID NOT IN (SELECT id FROM tags)")
            try db.execute(sql: "DELETE FROM album_artists WHERE albumID NOT IN (SELECT plexID FROM albums)")
            try db.execute(sql: "DELETE FROM album_artists WHERE artistID NOT IN (SELECT plexID FROM artists)")
            try db.execute(sql: "DELETE FROM album_collections WHERE albumID NOT IN (SELECT plexID FROM albums)")
            try db.execute(sql: "DELETE FROM album_collections WHERE collectionID NOT IN (SELECT plexID FROM collections)")
            try db.execute(sql: "DELETE FROM playlist_items WHERE playlistID NOT IN (SELECT plexID FROM playlists)")

            try LibraryMetadataRecord(
                key: LibraryStoreMigrations.lastIncrementalPrunedAlbumCountMetadataKey,
                value: String(staleAlbumIDs.count)
            ).save(db)
            try LibraryMetadataRecord(
                key: LibraryStoreMigrations.lastIncrementalPrunedTrackCountMetadataKey,
                value: String(staleTrackIDs.count)
            ).save(db)

            return LibrarySyncPruneResult(prunedAlbumIDs: staleAlbumIDs, prunedTrackIDs: staleTrackIDs)
        }
    }

    func setSyncCheckpoint(_ checkpoint: LibrarySyncCheckpoint, in run: LibrarySyncRun?) async throws {
        try await dbQueue.write { db in
            try LibrarySyncCheckpointRecord(checkpoint: checkpoint, runID: run?.id).save(db)
        }
    }

    func syncCheckpoint(forKey key: String) async throws -> LibrarySyncCheckpoint? {
        try await dbQueue.read { db in
            try LibrarySyncCheckpointRecord.fetchOne(db, key: key)?.model
        }
    }

    func completeIncrementalSync(_ run: LibrarySyncRun, refreshedAt: Date) async throws {
        let refreshedInterval = String(refreshedAt.timeIntervalSince1970)

        try await dbQueue.write { db in
            try LibraryMetadataRecord(
                key: LibraryStoreMigrations.lastRefreshMetadataKey,
                value: refreshedInterval
            ).save(db)
            try LibraryMetadataRecord(
                key: LibraryStoreMigrations.lastIncrementalRunIDMetadataKey,
                value: run.id
            ).save(db)
        }
    }
}
