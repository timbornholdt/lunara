import Foundation
import GRDB

enum LibraryStoreMigrations {
    nonisolated static let lastRefreshMetadataKey = "last_refresh"
    nonisolated static let lastIncrementalRunIDMetadataKey = "incremental_last_run_id"
    nonisolated static let lastIncrementalPrunedAlbumCountMetadataKey = "incremental_last_pruned_album_count"
    nonisolated static let lastIncrementalPrunedTrackCountMetadataKey = "incremental_last_pruned_track_count"

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_library_core") { db in
            try db.create(table: "albums") { table in
                table.column("plexID", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("artistName", .text).notNull()
                table.column("year", .integer)
                table.column("thumbURL", .text)
                table.column("genre", .text)
                table.column("rating", .integer)
                table.column("addedAt", .datetime)
                table.column("trackCount", .integer).notNull()
                table.column("duration", .double).notNull()
            }

            try db.create(index: "albums_artist_title_idx", on: "albums", columns: ["artistName", "title"])

            try db.create(table: "tracks") { table in
                table.column("plexID", .text).primaryKey()
                table.column("albumID", .text).notNull().indexed().references("albums", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("trackNumber", .integer).notNull()
                table.column("duration", .double).notNull()
                table.column("artistName", .text).notNull()
                table.column("key", .text).notNull()
                table.column("thumbURL", .text)
            }

            try db.create(index: "tracks_album_order_idx", on: "tracks", columns: ["albumID", "trackNumber", "title"])

            try db.create(table: "artists") { table in
                table.column("plexID", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("sortName", .text)
                table.column("thumbURL", .text)
                table.column("genre", .text)
                table.column("summary", .text)
                table.column("albumCount", .integer).notNull()
            }

            try db.create(index: "artists_sort_idx", on: "artists", columns: ["sortName", "name"])

            try db.create(table: "collections") { table in
                table.column("plexID", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("thumbURL", .text)
                table.column("summary", .text)
                table.column("albumCount", .integer).notNull()
                table.column("updatedAt", .datetime)
            }

            try db.create(index: "collections_title_idx", on: "collections", columns: ["title"])

            try db.create(table: "artwork_paths") { table in
                table.column("ownerID", .text).notNull()
                table.column("ownerType", .text).notNull()
                table.column("variant", .text).notNull()
                table.column("path", .text).notNull()
                table.primaryKey(["ownerID", "ownerType", "variant"])
            }

            try db.create(table: "library_metadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_album_metadata_fields") { db in
            try db.alter(table: "albums") { table in
                table.add(column: "review", .text)
                table.add(column: "genres", .text).notNull().defaults(to: "[]")
                table.add(column: "styles", .text).notNull().defaults(to: "[]")
                table.add(column: "moods", .text).notNull().defaults(to: "[]")
            }
        }

        migrator.registerMigration("v3_incremental_sync_bookkeeping") { db in
            try db.alter(table: "albums") { table in
                table.add(column: "lastSeenSyncID", .text)
                table.add(column: "lastSeenAt", .datetime)
            }
            try db.create(index: "albums_seen_sync_idx", on: "albums", columns: ["lastSeenSyncID"])

            try db.alter(table: "tracks") { table in
                table.add(column: "lastSeenSyncID", .text)
                table.add(column: "lastSeenAt", .datetime)
            }
            try db.create(index: "tracks_seen_sync_idx", on: "tracks", columns: ["lastSeenSyncID"])

            try db.create(table: "library_sync_checkpoints") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("runID", .text)
            }
        }

        migrator.registerMigration("v4_search_query_indexes") { db in
            try db.alter(table: "albums") { table in
                table.add(column: "titleSearch", .text).notNull().defaults(to: "")
                table.add(column: "artistNameSearch", .text).notNull().defaults(to: "")
            }

            try db.alter(table: "artists") { table in
                table.add(column: "nameSearch", .text).notNull().defaults(to: "")
                table.add(column: "sortNameSearch", .text).notNull().defaults(to: "")
            }

            try db.alter(table: "collections") { table in
                table.add(column: "titleSearch", .text).notNull().defaults(to: "")
            }

            let albumRows = try Row.fetchAll(db, sql: "SELECT plexID, title, artistName FROM albums")
            for row in albumRows {
                let plexID: String = row["plexID"]
                let title: String = row["title"]
                let artistName: String = row["artistName"]
                try db.execute(
                    sql: "UPDATE albums SET titleSearch = ?, artistNameSearch = ? WHERE plexID = ?",
                    arguments: [
                        LibraryStoreSearchNormalizer.normalize(title),
                        LibraryStoreSearchNormalizer.normalize(artistName),
                        plexID
                    ]
                )
            }

            let artistRows = try Row.fetchAll(db, sql: "SELECT plexID, name, sortName FROM artists")
            for row in artistRows {
                let plexID: String = row["plexID"]
                let name: String = row["name"]
                let sortName: String = row["sortName"] ?? ""
                try db.execute(
                    sql: "UPDATE artists SET nameSearch = ?, sortNameSearch = ? WHERE plexID = ?",
                    arguments: [
                        LibraryStoreSearchNormalizer.normalize(name),
                        LibraryStoreSearchNormalizer.normalize(sortName),
                        plexID
                    ]
                )
            }

            let collectionRows = try Row.fetchAll(db, sql: "SELECT plexID, title FROM collections")
            for row in collectionRows {
                let plexID: String = row["plexID"]
                let title: String = row["title"]
                try db.execute(
                    sql: "UPDATE collections SET titleSearch = ? WHERE plexID = ?",
                    arguments: [LibraryStoreSearchNormalizer.normalize(title), plexID]
                )
            }

            try db.create(index: "albums_title_search_idx", on: "albums", columns: ["titleSearch"])
            try db.create(index: "albums_artist_search_idx", on: "albums", columns: ["artistNameSearch"])
            try db.create(index: "artists_name_search_idx", on: "artists", columns: ["nameSearch"])
            try db.create(index: "artists_sort_name_search_idx", on: "artists", columns: ["sortNameSearch"])
            try db.create(index: "collections_title_search_idx", on: "collections", columns: ["titleSearch"])
        }

        migrator.registerMigration("v5_relationship_reconciliation") { db in
            try db.alter(table: "artists") { table in
                table.add(column: "lastSeenSyncID", .text)
                table.add(column: "lastSeenAt", .datetime)
            }
            try db.create(index: "artists_seen_sync_idx", on: "artists", columns: ["lastSeenSyncID"])

            try db.alter(table: "collections") { table in
                table.add(column: "lastSeenSyncID", .text)
                table.add(column: "lastSeenAt", .datetime)
            }
            try db.create(index: "collections_seen_sync_idx", on: "collections", columns: ["lastSeenSyncID"])

            try db.create(table: "tags") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("kind", .text).notNull()
                table.column("name", .text).notNull()
                table.column("normalizedName", .text).notNull()
                table.column("lastSeenSyncID", .text)
                table.column("lastSeenAt", .datetime)
                table.uniqueKey(["kind", "normalizedName"])
            }
            try db.create(index: "tags_kind_normalized_idx", on: "tags", columns: ["kind", "normalizedName"])
            try db.create(index: "tags_seen_sync_idx", on: "tags", columns: ["lastSeenSyncID"])

            try db.create(table: "album_tags") { table in
                table.column("albumID", .text).notNull().references("albums", column: "plexID", onDelete: .cascade)
                table.column("tagID", .integer).notNull().references("tags", column: "id", onDelete: .cascade)
                table.column("lastSeenSyncID", .text)
                table.column("lastSeenAt", .datetime)
                table.primaryKey(["albumID", "tagID"])
            }
            try db.create(index: "album_tags_tag_album_idx", on: "album_tags", columns: ["tagID", "albumID"])
            try db.create(index: "album_tags_seen_sync_idx", on: "album_tags", columns: ["lastSeenSyncID"])

            try db.create(table: "album_artists") { table in
                table.column("albumID", .text).notNull().references("albums", column: "plexID", onDelete: .cascade)
                table.column("artistID", .text).notNull().references("artists", column: "plexID", onDelete: .cascade)
                table.column("lastSeenSyncID", .text)
                table.column("lastSeenAt", .datetime)
                table.primaryKey(["albumID", "artistID"])
            }
            try db.create(index: "album_artists_artist_album_idx", on: "album_artists", columns: ["artistID", "albumID"])
            try db.create(index: "album_artists_seen_sync_idx", on: "album_artists", columns: ["lastSeenSyncID"])

            try db.create(table: "album_collections") { table in
                table.column("albumID", .text).notNull().references("albums", column: "plexID", onDelete: .cascade)
                table.column("collectionID", .text).notNull().references("collections", column: "plexID", onDelete: .cascade)
                table.column("lastSeenSyncID", .text)
                table.column("lastSeenAt", .datetime)
                table.primaryKey(["albumID", "collectionID"])
            }
            try db.create(index: "album_collections_collection_album_idx", on: "album_collections", columns: ["collectionID", "albumID"])
            try db.create(index: "album_collections_seen_sync_idx", on: "album_collections", columns: ["lastSeenSyncID"])

            try db.create(table: "playlists") { table in
                table.column("plexID", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("trackCount", .integer).notNull()
                table.column("updatedAt", .datetime)
                table.column("lastSeenSyncID", .text)
                table.column("lastSeenAt", .datetime)
            }
            try db.create(index: "playlists_seen_sync_idx", on: "playlists", columns: ["lastSeenSyncID"])

            try db.create(table: "playlist_items") { table in
                table.column("playlistID", .text).notNull().references("playlists", column: "plexID", onDelete: .cascade)
                table.column("trackID", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("lastSeenSyncID", .text)
                table.column("lastSeenAt", .datetime)
                table.primaryKey(["playlistID", "position"])
            }
            try db.create(index: "playlist_items_playlist_position_idx", on: "playlist_items", columns: ["playlistID", "position"])
            try db.create(index: "playlist_items_seen_sync_idx", on: "playlist_items", columns: ["lastSeenSyncID"])
        }

        migrator.registerMigration("v6_album_release_date") { db in
            try db.alter(table: "albums") { table in
                table.add(column: "releaseDate", .datetime)
            }
        }

        migrator.registerMigration("v7_offline_tracks") { db in
            try db.create(table: "offline_tracks") { table in
                table.column("trackID", .text).primaryKey()
                table.column("albumID", .text).notNull()
                table.column("filename", .text).notNull()
                table.column("downloadedAt", .datetime).notNull()
                table.column("fileSizeBytes", .integer).notNull()
            }

            try db.create(index: "offline_tracks_album_idx", on: "offline_tracks", columns: ["albumID"])
        }

        migrator.registerMigration("v8_synced_collections") { db in
            try db.create(table: "synced_collections") { table in
                table.column("collectionID", .text).primaryKey()
                table.column("syncedAt", .datetime).notNull()
            }
        }

        return migrator
    }
}
