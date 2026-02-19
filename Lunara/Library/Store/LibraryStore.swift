import Foundation
import GRDB

final class LibraryStore: LibraryStoreProtocol {
    let dbQueue: DatabaseQueue

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

    func track(id: String) async throws -> Track? {
        throw LibraryError.operationFailed(
            reason: "Stage 5B pending: LibraryStore.track(id:) query path is not implemented yet."
        )
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

    func collection(id: String) async throws -> Collection? {
        throw LibraryError.operationFailed(
            reason: "Stage 5B pending: LibraryStore.collection(id:) query path is not implemented yet."
        )
    }

    func searchAlbums(query: String) async throws -> [Album] {
        let _ = query
        throw LibraryError.operationFailed(
            reason: "Stage 5B pending: LibraryStore.searchAlbums(query:) is not implemented yet."
        )
    }

    func searchArtists(query: String) async throws -> [Artist] {
        let _ = query
        throw LibraryError.operationFailed(
            reason: "Stage 5B pending: LibraryStore.searchArtists(query:) is not implemented yet."
        )
    }

    func searchCollections(query: String) async throws -> [Collection] {
        let _ = query
        throw LibraryError.operationFailed(
            reason: "Stage 5B pending: LibraryStore.searchCollections(query:) is not implemented yet."
        )
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
