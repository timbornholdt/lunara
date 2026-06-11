import Foundation
import GRDB

// MARK: - Artist enrichment cache (Lunara-ya7)

extension LibraryStore {
    func cachedArtistEnrichment(name: String) async throws -> ArtistEnrichmentCacheEntry? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM artist_enrichment WHERE artistName = ?",
                arguments: [name]
            ) else {
                return nil
            }

            let enrichment: MusicBrainzArtistEnrichment? = (row["mbid"] as String?).map { mbid in
                let albumsJSON: String = row["albumsJSON"] ?? "[]"
                let albums = (try? JSONDecoder().decode([ExternalReleaseGroup].self, from: Data(albumsJSON.utf8))) ?? []
                return MusicBrainzArtistEnrichment(
                    artistID: mbid,
                    wikipediaURL: (row["wikipediaURL"] as String?).flatMap(URL.init(string:)),
                    homepageURL: (row["homepageURL"] as String?).flatMap(URL.init(string:)),
                    albums: albums
                )
            }

            return ArtistEnrichmentCacheEntry(
                enrichment: enrichment,
                lastFMBio: row["lastFMBio"],
                fetchedAt: row["fetchedAt"]
            )
        }
    }

    func saveArtistEnrichment(_ enrichment: MusicBrainzArtistEnrichment, name: String) async throws {
        let albumsData = (try? JSONEncoder().encode(enrichment.albums)) ?? Data("[]".utf8)
        let albumsJSON = String(decoding: albumsData, as: UTF8.self)
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO artist_enrichment (artistName, mbid, wikipediaURL, homepageURL, albumsJSON, fetchedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(artistName) DO UPDATE SET
                    mbid = excluded.mbid,
                    wikipediaURL = excluded.wikipediaURL,
                    homepageURL = excluded.homepageURL,
                    albumsJSON = excluded.albumsJSON,
                    fetchedAt = excluded.fetchedAt
                """,
                arguments: [
                    name,
                    enrichment.artistID,
                    enrichment.wikipediaURL?.absoluteString,
                    enrichment.homepageURL?.absoluteString,
                    albumsJSON,
                    Date()
                ]
            )
        }
    }

    /// Bio saves never freshen the enrichment's fetchedAt — a bio-only row gets
    /// the epoch so the MusicBrainz refresh still triggers on next visit.
    func saveArtistLastFMBio(_ bio: String, name: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO artist_enrichment (artistName, lastFMBio, fetchedAt)
                VALUES (?, ?, ?)
                ON CONFLICT(artistName) DO UPDATE SET lastFMBio = excluded.lastFMBio
                """,
                arguments: [name, bio, Date(timeIntervalSince1970: 0)]
            )
        }
    }
}
