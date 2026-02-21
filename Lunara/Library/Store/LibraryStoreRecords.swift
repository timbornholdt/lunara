import Foundation
import GRDB

struct AlbumRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "albums"

    let plexID: String
    let title: String
    let artistName: String
    let titleSearch: String
    let artistNameSearch: String
    let year: Int?
    let releaseDate: Date?
    let thumbURL: String?
    let genre: String?
    let review: String?
    let genres: String
    let styles: String
    let moods: String
    let rating: Int?
    let addedAt: Date?
    let trackCount: Int
    let duration: TimeInterval

    init(model: Album) {
        plexID = model.plexID
        title = model.title
        artistName = model.artistName
        titleSearch = LibraryStoreSearchNormalizer.normalize(model.title)
        artistNameSearch = LibraryStoreSearchNormalizer.normalize(model.artistName)
        year = model.year
        releaseDate = model.releaseDate
        thumbURL = model.thumbURL
        genre = model.genre
        review = model.review
        genres = Self.encodedTags(model.genres)
        styles = Self.encodedTags(model.styles)
        moods = Self.encodedTags(model.moods)
        rating = model.rating
        addedAt = model.addedAt
        trackCount = model.trackCount
        duration = model.duration
    }

    var model: Album {
        Album(
            plexID: plexID,
            title: title,
            artistName: artistName,
            year: year,
            releaseDate: releaseDate,
            thumbURL: thumbURL,
            genre: genre,
            rating: rating,
            addedAt: addedAt,
            trackCount: trackCount,
            duration: duration,
            review: review,
            genres: Self.decodedTags(genres),
            styles: Self.decodedTags(styles),
            moods: Self.decodedTags(moods)
        )
    }

    private static func encodedTags(_ values: [String]) -> String {
        do {
            let data = try JSONEncoder().encode(values)
            guard let string = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return string
        } catch {
            return "[]"
        }
    }

    private static func decodedTags(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            return []
        }
    }
}

struct TrackRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "tracks"

    let plexID: String
    let albumID: String
    let title: String
    let trackNumber: Int
    let duration: TimeInterval
    let artistName: String
    let key: String
    let thumbURL: String?

    init(model: Track) {
        plexID = model.plexID
        albumID = model.albumID
        title = model.title
        trackNumber = model.trackNumber
        duration = model.duration
        artistName = model.artistName
        key = model.key
        thumbURL = model.thumbURL
    }

    var model: Track {
        Track(
            plexID: plexID,
            albumID: albumID,
            title: title,
            trackNumber: trackNumber,
            duration: duration,
            artistName: artistName,
            key: key,
            thumbURL: thumbURL
        )
    }
}

struct ArtistRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "artists"

    let plexID: String
    let name: String
    let sortName: String?
    let nameSearch: String
    let sortNameSearch: String
    let thumbURL: String?
    let genre: String?
    let summary: String?
    let albumCount: Int

    init(model: Artist) {
        plexID = model.plexID
        name = model.name
        sortName = model.sortName
        nameSearch = LibraryStoreSearchNormalizer.normalize(model.name)
        sortNameSearch = LibraryStoreSearchNormalizer.normalize(model.sortName ?? "")
        thumbURL = model.thumbURL
        genre = model.genre
        summary = model.summary
        albumCount = model.albumCount
    }

    var model: Artist {
        Artist(
            plexID: plexID,
            name: name,
            sortName: sortName,
            thumbURL: thumbURL,
            genre: genre,
            summary: summary,
            albumCount: albumCount
        )
    }
}

struct CollectionRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "collections"

    let plexID: String
    let title: String
    let titleSearch: String
    let thumbURL: String?
    let summary: String?
    let albumCount: Int
    let updatedAt: Date?

    init(model: Collection) {
        plexID = model.plexID
        title = model.title
        titleSearch = LibraryStoreSearchNormalizer.normalize(model.title)
        thumbURL = model.thumbURL
        summary = model.summary
        albumCount = model.albumCount
        updatedAt = model.updatedAt
    }

    var model: Collection {
        Collection(
            plexID: plexID,
            title: title,
            thumbURL: thumbURL,
            summary: summary,
            albumCount: albumCount,
            updatedAt: updatedAt
        )
    }
}

struct ArtworkPathRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "artwork_paths"

    let ownerID: String
    let ownerType: String
    let variant: String
    let path: String

    init(key: ArtworkKey, path: String) {
        ownerID = key.ownerID
        ownerType = key.ownerType.rawValue
        variant = key.variant.rawValue
        self.path = path
    }
}

struct LibraryMetadataRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "library_metadata"

    let key: String
    let value: String
}

struct LibrarySyncCheckpointRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "library_sync_checkpoints"

    let key: String
    let value: String
    let updatedAt: Date
    let runID: String?

    init(checkpoint: LibrarySyncCheckpoint, runID: String?) {
        key = checkpoint.key
        value = checkpoint.value
        updatedAt = checkpoint.updatedAt
        self.runID = runID
    }

    var model: LibrarySyncCheckpoint {
        LibrarySyncCheckpoint(key: key, value: value, updatedAt: updatedAt)
    }
}
