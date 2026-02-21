import Foundation
import GRDB

final class OfflineStore: OfflineStoreProtocol, @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let offlineDirectory: URL

    init(dbQueue: DatabaseQueue, offlineDirectory: URL) {
        self.dbQueue = dbQueue
        self.offlineDirectory = offlineDirectory
    }

    func localFileURL(forTrackID trackID: String) async throws -> URL? {
        let targetID = trackID
        let record = try await dbQueue.read { db in
            try OfflineTrackRecord.fetchOne(db, key: targetID)
        }

        guard let record else { return nil }

        let fileURL = offlineDirectory.appendingPathComponent(record.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        // Stale row: file is missing on disk — clean up
        let staleID = record.trackID
        try await dbQueue.write { db in
            _ = try OfflineTrackRecord.deleteOne(db, key: staleID)
        }
        return nil
    }

    func offlineStatus(forAlbum albumID: String, totalTrackCount: Int) async throws -> OfflineAlbumStatus {
        let targetAlbumID = albumID
        let downloadedCount = try await dbQueue.read { db -> Int in
            try OfflineTrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .fetchCount(db)
        }

        if downloadedCount == 0 {
            return .notDownloaded
        } else if downloadedCount >= totalTrackCount {
            return .downloaded
        } else {
            return .partiallyDownloaded(downloadedCount: downloadedCount, totalCount: totalTrackCount)
        }
    }

    func saveOfflineTrack(_ offlineTrack: OfflineTrack) async throws {
        let record = OfflineTrackRecord(model: offlineTrack)
        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    func deleteOfflineTracks(forAlbum albumID: String) async throws {
        let targetAlbumID = albumID

        // Fetch filenames first so we can delete files
        let records = try await dbQueue.read { db in
            try OfflineTrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .fetchAll(db)
        }

        // Delete files
        let fm = FileManager.default
        for record in records {
            let fileURL = offlineDirectory.appendingPathComponent(record.filename)
            try? fm.removeItem(at: fileURL)
        }

        // Delete DB rows
        try await dbQueue.write { db in
            _ = try OfflineTrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .deleteAll(db)
        }
    }

    func totalOfflineStorageBytes() async throws -> Int64 {
        try await dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT COALESCE(SUM(fileSizeBytes), 0) AS total FROM offline_tracks")
            return row?["total"] ?? 0
        }
    }

    func offlineTracks(forAlbum albumID: String) async throws -> [OfflineTrack] {
        let targetAlbumID = albumID
        return try await dbQueue.read { db in
            let records = try OfflineTrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func allOfflineAlbumIDs() async throws -> [String] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT DISTINCT albumID FROM offline_tracks ORDER BY albumID")
            return rows.map { row in row["albumID"] as String }
        }
    }

    // MARK: - Synced Collections

    func syncedCollectionIDs() async throws -> [String] {
        try await dbQueue.read { db in
            let records = try SyncedCollectionRecord.fetchAll(db)
            return records.map(\.collectionID)
        }
    }

    func addSyncedCollection(_ collectionID: String) async throws {
        let record = SyncedCollectionRecord(collectionID: collectionID, syncedAt: Date())
        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    func removeSyncedCollection(_ collectionID: String) async throws {
        let targetID = collectionID
        try await dbQueue.write { db in
            _ = try SyncedCollectionRecord.deleteOne(db, key: targetID)
        }
    }

    func isSyncedCollection(_ collectionID: String) async throws -> Bool {
        let targetID = collectionID
        return try await dbQueue.read { db in
            try SyncedCollectionRecord.fetchOne(db, key: targetID) != nil
        }
    }

    func collectionIDs(forAlbum albumID: String) async throws -> [String] {
        let targetAlbumID = albumID
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT collectionID FROM album_collections WHERE albumID = ?",
                arguments: [targetAlbumID]
            )
            return rows.map { $0["collectionID"] as String }
        }
    }
}
