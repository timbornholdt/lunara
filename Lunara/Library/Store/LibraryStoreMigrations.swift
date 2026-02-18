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

        return migrator
    }
}
