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

    func upsertAlbum(_ album: Album) async throws {
        let target = album
        try await dbQueue.write { db in
            try AlbumRecord(model: target).save(db)
            try MainActor.assumeIsolated {
                try LibraryStore.reconcileAlbumTags(for: [target], syncID: nil, syncDate: nil, db: db)
            }
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
        try await dbQueue.read { db in
            try TrackRecord.fetchOne(db, key: id)?.model
        }
    }

    func replaceTracks(_ tracks: [Track], forAlbum albumID: String) async throws {
        let targetAlbumID = albumID
        let replacementTracks = tracks
        try await dbQueue.write { db in
            _ = try TrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .deleteAll(db)

            for track in replacementTracks {
                try TrackRecord(model: track).save(db)
            }
        }
    }

    func fetchArtists() async throws -> [Artist] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.*,
                       COALESCE(ac.cnt, 0) AS computedAlbumCount
                FROM artists a
                LEFT JOIN (
                    SELECT artistName, COUNT(*) AS cnt
                    FROM albums
                    GROUP BY artistName
                ) ac ON ac.artistName = a.name
                ORDER BY COALESCE(a.sortName, a.name) ASC, a.name ASC
                """)
            return try rows.map { row in
                let record = try ArtistRecord(row: row)
                let base = record.model
                let count: Int = row["computedAlbumCount"]
                return Artist(
                    plexID: base.plexID,
                    name: base.name,
                    sortName: base.sortName,
                    thumbURL: base.thumbURL,
                    genre: base.genre,
                    summary: base.summary,
                    albumCount: count
                )
            }
        }
    }

    func fetchAlbumsByArtistName(_ artistName: String) async throws -> [Album] {
        let targetName = artistName
        return try await dbQueue.read { db in
            let records = try AlbumRecord
                .filter(Column("artistName") == targetName)
                .order(Column("year").asc, Column("title").asc, Column("plexID").asc)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func fetchArtist(id: String) async throws -> Artist? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT a.*,
                       (SELECT COUNT(*) FROM albums WHERE artistName = a.name) AS computedAlbumCount
                FROM artists a
                WHERE a.plexID = ?
                """, arguments: [id]) else {
                return nil
            }
            let record = try ArtistRecord(row: row)
            let base = record.model
            let count: Int = row["computedAlbumCount"]
            return Artist(
                plexID: base.plexID,
                name: base.name,
                sortName: base.sortName,
                thumbURL: base.thumbURL,
                genre: base.genre,
                summary: base.summary,
                albumCount: count
            )
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
        try await dbQueue.read { db in
            try CollectionRecord.fetchOne(db, key: id)?.model
        }
    }

    func searchAlbums(query: String) async throws -> [Album] {
        try await queryAlbums(filter: AlbumQueryFilter(textQuery: query))
    }

    func searchArtists(query: String) async throws -> [Artist] {
        let normalizedQuery = LibraryStoreSearchNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return try await fetchArtists()
        }

        let pattern = LibraryStoreSearchNormalizer.likeContainsPattern(for: normalizedQuery)
        return try await dbQueue.read { db in
            let records = try ArtistRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM artists
                WHERE nameSearch LIKE ? ESCAPE '\\'
                   OR sortNameSearch LIKE ? ESCAPE '\\'
                ORDER BY sortName ASC, name ASC
                """,
                arguments: [pattern, pattern]
            )
            return records.map(\.model)
        }
    }

    func searchCollections(query: String) async throws -> [Collection] {
        let normalizedQuery = LibraryStoreSearchNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return try await fetchCollections()
        }

        let pattern = LibraryStoreSearchNormalizer.likeContainsPattern(for: normalizedQuery)
        return try await dbQueue.read { db in
            let records = try CollectionRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM collections
                WHERE titleSearch LIKE ? ESCAPE '\\'
                ORDER BY title ASC
                """,
                arguments: [pattern]
            )
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

    func fetchTags(kind: LibraryTagKind) async throws -> [String] {
        let kindValue = kind.rawValue
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT name FROM tags WHERE kind = ? ORDER BY name ASC",
                arguments: [kindValue]
            )
            return rows.map { row in
                let name: String = row["name"]
                return name
            }
        }
    }

    func fetchPlaylists() async throws -> [LibraryPlaylistSnapshot] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT plexID, title, trackCount, updatedAt FROM playlists ORDER BY title ASC"
            )
            return rows.map { row in
                LibraryPlaylistSnapshot(
                    plexID: row["plexID"],
                    title: row["title"],
                    trackCount: row["trackCount"],
                    updatedAt: row["updatedAt"]
                )
            }
        }
    }

    func fetchPlaylistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] {
        let targetID = playlistID
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT trackID, position FROM playlist_items WHERE playlistID = ? ORDER BY position ASC",
                arguments: [targetID]
            )
            return rows.map { row in
                LibraryPlaylistItemSnapshot(trackID: row["trackID"], position: row["position"])
            }
        }
    }
}
