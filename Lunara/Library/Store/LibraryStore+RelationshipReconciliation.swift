import Foundation
import GRDB

extension LibraryStore {
    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws {
        try await dbQueue.write { db in
            for album in albums {
                try AlbumRecord(model: album).save(db)
            }
            try LibraryStore.reconcileAlbumTags(for: albums, in: run, db: db)
        }
    }

    func replaceArtists(_ artists: [Artist], in run: LibrarySyncRun) async throws {
        try await dbQueue.write { db in
            for artist in artists {
                try db.execute(
                    sql: """
                    INSERT INTO artists (plexID, name, sortName, nameSearch, sortNameSearch, thumbURL, genre, summary, albumCount, lastSeenSyncID, lastSeenAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(plexID) DO UPDATE SET
                        name = excluded.name,
                        sortName = excluded.sortName,
                        nameSearch = excluded.nameSearch,
                        sortNameSearch = excluded.sortNameSearch,
                        thumbURL = excluded.thumbURL,
                        genre = excluded.genre,
                        summary = excluded.summary,
                        albumCount = excluded.albumCount,
                        lastSeenSyncID = excluded.lastSeenSyncID,
                        lastSeenAt = excluded.lastSeenAt
                    """,
                    arguments: [
                        artist.plexID,
                        artist.name,
                        artist.sortName,
                        LibraryStoreSearchNormalizer.normalize(artist.name),
                        LibraryStoreSearchNormalizer.normalize(artist.sortName ?? ""),
                        artist.thumbURL,
                        artist.genre,
                        artist.summary,
                        artist.albumCount,
                        run.id,
                        run.startedAt
                    ]
                )
            }
        }
    }

    func replaceCollections(_ collections: [Collection], in run: LibrarySyncRun) async throws {
        try await dbQueue.write { db in
            for collection in collections {
                try db.execute(
                    sql: """
                    INSERT INTO collections (plexID, title, titleSearch, thumbURL, summary, albumCount, updatedAt, lastSeenSyncID, lastSeenAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(plexID) DO UPDATE SET
                        title = excluded.title,
                        titleSearch = excluded.titleSearch,
                        thumbURL = excluded.thumbURL,
                        summary = excluded.summary,
                        albumCount = excluded.albumCount,
                        updatedAt = excluded.updatedAt,
                        lastSeenSyncID = excluded.lastSeenSyncID,
                        lastSeenAt = excluded.lastSeenAt
                    """,
                    arguments: [
                        collection.plexID,
                        collection.title,
                        LibraryStoreSearchNormalizer.normalize(collection.title),
                        collection.thumbURL,
                        collection.summary,
                        collection.albumCount,
                        collection.updatedAt,
                        run.id,
                        run.startedAt
                    ]
                )
            }
        }
    }

    func upsertAlbumCollections(_ albumCollectionIDs: [String: [String]], in run: LibrarySyncRun) async throws {
        guard !albumCollectionIDs.isEmpty else {
            return
        }
        try await dbQueue.write { db in
            for (albumID, collectionIDs) in albumCollectionIDs {
                for collectionID in collectionIDs {
                    try db.execute(
                        sql: """
                        INSERT INTO album_collections (albumID, collectionID, lastSeenSyncID, lastSeenAt)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(albumID, collectionID) DO UPDATE SET
                            lastSeenSyncID = excluded.lastSeenSyncID,
                            lastSeenAt = excluded.lastSeenAt
                        """,
                        arguments: [albumID, collectionID, run.id, run.startedAt]
                    )
                }
            }
        }
    }

    func upsertPlaylists(_ playlists: [LibraryPlaylistSnapshot], in run: LibrarySyncRun) async throws {
        try await dbQueue.write { db in
            for playlist in playlists {
                try db.execute(
                    sql: """
                    INSERT INTO playlists (plexID, title, trackCount, updatedAt, lastSeenSyncID, lastSeenAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(plexID) DO UPDATE SET
                        title = excluded.title,
                        trackCount = excluded.trackCount,
                        updatedAt = excluded.updatedAt,
                        lastSeenSyncID = excluded.lastSeenSyncID,
                        lastSeenAt = excluded.lastSeenAt
                    """,
                    arguments: [playlist.plexID, playlist.title, playlist.trackCount, playlist.updatedAt, run.id, run.startedAt]
                )
            }
        }
    }

    func upsertPlaylistItems(
        _ items: [LibraryPlaylistItemSnapshot],
        playlistID: String,
        in run: LibrarySyncRun
    ) async throws {
        try await dbQueue.write { db in
            for item in items {
                try db.execute(
                    sql: """
                    INSERT INTO playlist_items (playlistID, trackID, position, lastSeenSyncID, lastSeenAt)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(playlistID, position) DO UPDATE SET
                        trackID = excluded.trackID,
                        lastSeenSyncID = excluded.lastSeenSyncID,
                        lastSeenAt = excluded.lastSeenAt
                    """,
                    arguments: [playlistID, item.trackID, item.position, run.id, run.startedAt]
                )
            }
        }
    }

    private static func reconcileAlbumTags(for albums: [Album], in run: LibrarySyncRun, db: Database) throws {
        try reconcileAlbumTags(for: albums, syncID: run.id, syncDate: run.startedAt, db: db)
    }

    static func reconcileAlbumTags(for albums: [Album], syncID: String?, syncDate: Date?, db: Database) throws {
        let canonicalTags = buildCanonicalTagNames(for: albums)
        guard !canonicalTags.isEmpty else {
            return
        }

        var tagIDByKey: [TagIdentity: Int64] = [:]
        for (identity, canonicalName) in canonicalTags {
            try db.execute(
                sql: """
                INSERT INTO tags (kind, name, normalizedName, lastSeenSyncID, lastSeenAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(kind, normalizedName) DO UPDATE SET
                    name = excluded.name,
                    lastSeenSyncID = COALESCE(excluded.lastSeenSyncID, tags.lastSeenSyncID),
                    lastSeenAt = COALESCE(excluded.lastSeenAt, tags.lastSeenAt)
                """,
                arguments: [identity.kind.rawValue, canonicalName, identity.normalizedName, syncID, syncDate]
            )

            let tagID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE kind = ? AND normalizedName = ?",
                arguments: [identity.kind.rawValue, identity.normalizedName]
            )
            guard let tagID else {
                throw LibraryError.databaseCorrupted
            }
            tagIDByKey[identity] = tagID
        }

        for album in albums {
            let albumTagIdentities = tagIdentities(for: album)
            for identity in albumTagIdentities {
                guard let tagID = tagIDByKey[identity] else {
                    throw LibraryError.databaseCorrupted
                }
                try db.execute(
                    sql: """
                    INSERT INTO album_tags (albumID, tagID, lastSeenSyncID, lastSeenAt)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(albumID, tagID) DO UPDATE SET
                        lastSeenSyncID = COALESCE(excluded.lastSeenSyncID, album_tags.lastSeenSyncID),
                        lastSeenAt = COALESCE(excluded.lastSeenAt, album_tags.lastSeenAt)
                    """,
                    arguments: [album.plexID, tagID, syncID, syncDate]
                )
            }
        }
    }

    private static func buildCanonicalTagNames(for albums: [Album]) -> [TagIdentity: String] {
        var rawNamesByIdentity: [TagIdentity: Set<String>] = [:]
        for album in albums {
            collectTagNames(kind: .genre, values: album.genres, into: &rawNamesByIdentity)
            collectTagNames(kind: .style, values: album.styles, into: &rawNamesByIdentity)
            collectTagNames(kind: .mood, values: album.moods, into: &rawNamesByIdentity)
        }

        var canonicalByIdentity: [TagIdentity: String] = [:]
        for (identity, rawValues) in rawNamesByIdentity {
            let sortedCandidates = rawValues.sorted { lhs, rhs in
                let lhsFolded = LibraryStoreSearchNormalizer.normalize(lhs)
                let rhsFolded = LibraryStoreSearchNormalizer.normalize(rhs)
                if lhsFolded != rhsFolded {
                    return lhsFolded < rhsFolded
                }
                let lhsLower = lhs.lowercased()
                let rhsLower = rhs.lowercased()
                if lhsLower != rhsLower {
                    return lhsLower < rhsLower
                }
                return lhs < rhs
            }
            if let canonical = sortedCandidates.first {
                canonicalByIdentity[identity] = canonical
            }
        }
        return canonicalByIdentity
    }

    private static func collectTagNames(
        kind: LibraryTagKind,
        values: [String],
        into map: inout [TagIdentity: Set<String>]
    ) {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let normalized = LibraryStoreSearchNormalizer.normalize(trimmed)
            guard !normalized.isEmpty else {
                continue
            }
            let identity = TagIdentity(kind: kind, normalizedName: normalized)
            map[identity, default: []].insert(trimmed)
        }
    }

    private static func tagIdentities(for album: Album) -> Set<TagIdentity> {
        var identities: Set<TagIdentity> = []
        appendTagIdentities(kind: .genre, values: album.genres, into: &identities)
        appendTagIdentities(kind: .style, values: album.styles, into: &identities)
        appendTagIdentities(kind: .mood, values: album.moods, into: &identities)
        return identities
    }

    private static func appendTagIdentities(
        kind: LibraryTagKind,
        values: [String],
        into identities: inout Set<TagIdentity>
    ) {
        for value in values {
            let normalized = LibraryStoreSearchNormalizer.normalize(value)
            guard !normalized.isEmpty else {
                continue
            }
            identities.insert(TagIdentity(kind: kind, normalizedName: normalized))
        }
    }
}

private struct TagIdentity: Hashable {
    let kind: LibraryTagKind
    let normalizedName: String
}

