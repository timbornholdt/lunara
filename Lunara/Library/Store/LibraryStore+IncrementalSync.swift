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

    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws {
        try await dbQueue.write { db in
            for album in albums {
                try AlbumRecord(model: album).save(db)
            }
        }
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
