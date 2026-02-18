import Foundation
import GRDB

final class LibraryStore: LibraryStoreProtocol {
    private let dbQueue: DatabaseQueue

    convenience init(databaseURL: URL) throws {
        try self.init(databasePath: databaseURL.path)
    }

    convenience init(databasePath: String) throws {
        let queue = try DatabaseQueue(path: databasePath)
        try self.init(databaseQueue: queue)
    }

    init(databaseQueue: DatabaseQueue) throws {
        dbQueue = databaseQueue
        try LibraryStoreMigrations.migrator().migrate(dbQueue)
    }

    static func inMemory() throws -> LibraryStore {
        try LibraryStore(databasePath: ":memory:")
    }

    func fetchAlbums(page: LibraryPage) async throws -> [Album] {
        let pageSize = page.size
        let pageOffset = page.offset

        return try await dbQueue.read { db in
            let records = try AlbumRecord
                .order(Column("artistName").asc, Column("title").asc)
                .limit(pageSize, offset: pageOffset)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func fetchAlbum(id: String) async throws -> Album? {
        try await dbQueue.read { db in
            try AlbumRecord.fetchOne(db, key: id)?.model
        }
    }

    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        let targetAlbumID = albumID

        return try await dbQueue.read { db in
            let records = try TrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .order(Column("trackNumber").asc, Column("title").asc)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func fetchArtists() async throws -> [Artist] {
        try await dbQueue.read { db in
            let records = try ArtistRecord
                .order(Column("sortName").asc, Column("name").asc)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func fetchArtist(id: String) async throws -> Artist? {
        try await dbQueue.read { db in
            try ArtistRecord.fetchOne(db, key: id)?.model
        }
    }

    func fetchCollections() async throws -> [Collection] {
        try await dbQueue.read { db in
            let records = try CollectionRecord
                .order(Column("title").asc)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func replaceLibrary(with snapshot: LibrarySnapshot, refreshedAt: Date) async throws {
        let albums = snapshot.albums
        let tracks = snapshot.tracks
        let artists = snapshot.artists
        let collections = snapshot.collections
        let refreshValue = String(refreshedAt.timeIntervalSince1970)

        try await dbQueue.write { db in
            try TrackRecord.deleteAll(db)
            try AlbumRecord.deleteAll(db)
            try ArtistRecord.deleteAll(db)
            try CollectionRecord.deleteAll(db)

            for album in albums {
                try AlbumRecord(model: album).insert(db)
            }

            for track in tracks {
                try TrackRecord(model: track).insert(db)
            }

            for artist in artists {
                try ArtistRecord(model: artist).insert(db)
            }

            for collection in collections {
                try CollectionRecord(model: collection).insert(db)
            }

            try LibraryMetadataRecord(
                key: LibraryStoreMigrations.lastRefreshMetadataKey,
                value: refreshValue
            ).save(db)
        }
    }

    func lastRefreshDate() async throws -> Date? {
        try await dbQueue.read { db in
            guard let metadata = try LibraryMetadataRecord.fetchOne(
                db,
                key: LibraryStoreMigrations.lastRefreshMetadataKey
            ) else {
                return nil
            }

            guard let interval = TimeInterval(metadata.value) else {
                return nil
            }

            return Date(timeIntervalSince1970: interval)
        }
    }

    func beginIncrementalSync(startedAt: Date) async throws -> LibrarySyncRun {
        LibrarySyncRun(startedAt: startedAt)
    }

    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws {
        throw LibraryError.operationFailed(reason: "Incremental album upsert is not implemented yet.")
    }

    func upsertTracks(_ tracks: [Track], in run: LibrarySyncRun) async throws {
        throw LibraryError.operationFailed(reason: "Incremental track upsert is not implemented yet.")
    }

    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws {
        throw LibraryError.operationFailed(reason: "Incremental seen-marker updates are not implemented yet.")
    }

    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws {
        throw LibraryError.operationFailed(reason: "Incremental seen-marker updates are not implemented yet.")
    }

    func pruneRowsNotSeen(in run: LibrarySyncRun) async throws -> LibrarySyncPruneResult {
        throw LibraryError.operationFailed(reason: "Incremental pruning is not implemented yet.")
    }

    func setSyncCheckpoint(_ checkpoint: LibrarySyncCheckpoint, in run: LibrarySyncRun?) async throws {
        throw LibraryError.operationFailed(reason: "Incremental sync checkpoints are not implemented yet.")
    }

    func syncCheckpoint(forKey key: String) async throws -> LibrarySyncCheckpoint? {
        throw LibraryError.operationFailed(reason: "Incremental sync checkpoints are not implemented yet.")
    }

    func completeIncrementalSync(_ run: LibrarySyncRun, refreshedAt: Date) async throws {
        throw LibraryError.operationFailed(reason: "Incremental sync completion is not implemented yet.")
    }

    func artworkPath(for key: ArtworkKey) async throws -> String? {
        let ownerID = key.ownerID
        let ownerType = key.ownerType.rawValue
        let variant = key.variant.rawValue

        return try await dbQueue.read { db in
            try ArtworkPathRecord
                .filter(Column("ownerID") == ownerID)
                .filter(Column("ownerType") == ownerType)
                .filter(Column("variant") == variant)
                .fetchOne(db)?
                .path
        }
    }

    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws {
        let ownerID = key.ownerID
        let ownerType = key.ownerType.rawValue
        let variant = key.variant.rawValue
        let targetPath = path

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO artwork_paths (ownerID, ownerType, variant, path)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(ownerID, ownerType, variant) DO UPDATE SET path = excluded.path
                """,
                arguments: [ownerID, ownerType, variant, targetPath]
            )
        }
    }

    func deleteArtworkPath(for key: ArtworkKey) async throws {
        let ownerID = key.ownerID
        let ownerType = key.ownerType.rawValue
        let variant = key.variant.rawValue

        try await dbQueue.write { db in
            _ = try ArtworkPathRecord
                .filter(Column("ownerID") == ownerID)
                .filter(Column("ownerType") == ownerType)
                .filter(Column("variant") == variant)
                .deleteAll(db)
        }
    }
}
