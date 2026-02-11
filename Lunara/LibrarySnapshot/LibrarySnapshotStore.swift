import Foundation

struct LibrarySnapshot: Codable, Sendable {
    struct Album: Codable, Sendable {
        let ratingKey: String
        let title: String
        let titleSort: String?
        let thumb: String?
        let art: String?
        let year: Int?
        let artist: String?
    }

    struct Collection: Codable, Sendable {
        let ratingKey: String
        let title: String
        let thumb: String?
        let art: String?
    }

    struct Artist: Codable, Sendable {
        let ratingKey: String
        let title: String
        let titleSort: String?
        let thumb: String?
        let art: String?
    }

    let albums: [Album]
    let collections: [Collection]
    let artists: [Artist]
    let musicSectionKey: String?
    let capturedAt: Date

    init(
        albums: [Album],
        collections: [Collection],
        artists: [Artist] = [],
        musicSectionKey: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.albums = albums
        self.collections = collections
        self.artists = artists
        self.musicSectionKey = musicSectionKey
        self.capturedAt = capturedAt
    }

    enum CodingKeys: String, CodingKey {
        case albums
        case collections
        case artists
        case musicSectionKey
        case capturedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        albums = try container.decode([Album].self, forKey: .albums)
        collections = try container.decode([Collection].self, forKey: .collections)
        artists = try container.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        musicSectionKey = try container.decodeIfPresent(String.self, forKey: .musicSectionKey)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
    }
}

protocol LibrarySnapshotStoring {
    func load() throws -> LibrarySnapshot?
    func save(_ snapshot: LibrarySnapshot) throws
    func clear() throws
}

final class LibrarySnapshotStore: LibrarySnapshotStoring {
    private let baseURL: URL
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let defaults: UserDefaults
    private let defaultsKey = "library.snapshot.data"

    init(baseURL: URL? = nil, fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        let resolvedBase: URL
        if let baseURL {
            resolvedBase = baseURL
        } else {
            resolvedBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lunara", isDirectory: true)
        }
        self.baseURL = resolvedBase
        self.fileManager = fileManager
        self.defaults = defaults
        self.snapshotURL = resolvedBase.appendingPathComponent("library-snapshot.json")
    }

    func load() throws -> LibrarySnapshot? {
        if let data = try? Data(contentsOf: snapshotURL),
           let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            return snapshot
        }
        if let data = defaults.data(forKey: defaultsKey) {
            return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        }
        return nil
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
        defaults.set(data, forKey: defaultsKey)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: snapshotURL.path) {
            try fileManager.removeItem(at: snapshotURL)
        }
        defaults.removeObject(forKey: defaultsKey)
    }
}

extension LibrarySnapshot.Album {
    init(album: PlexAlbum) {
        self.init(
            ratingKey: album.ratingKey,
            title: album.title,
            titleSort: album.titleSort,
            thumb: album.thumb,
            art: album.art,
            year: album.year,
            artist: album.artist
        )
    }

    func toPlexAlbum() -> PlexAlbum {
        PlexAlbum(
            ratingKey: ratingKey,
            title: title,
            thumb: thumb,
            art: art,
            year: year,
            artist: artist,
            titleSort: titleSort,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
            librarySectionID: nil,
            parentRatingKey: nil,
            studio: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
    }
}

extension LibrarySnapshot.Collection {
    init(collection: PlexCollection) {
        self.init(
            ratingKey: collection.ratingKey,
            title: collection.title,
            thumb: collection.thumb,
            art: collection.art
        )
    }

    func toPlexCollection() -> PlexCollection {
        PlexCollection(
            ratingKey: ratingKey,
            title: title,
            thumb: thumb,
            art: art,
            updatedAt: nil,
            key: nil
        )
    }
}

extension LibrarySnapshot.Artist {
    init(artist: PlexArtist) {
        self.init(
            ratingKey: artist.ratingKey,
            title: artist.title,
            titleSort: artist.titleSort,
            thumb: artist.thumb,
            art: artist.art
        )
    }

    func toPlexArtist() -> PlexArtist {
        PlexArtist(
            ratingKey: ratingKey,
            title: title,
            titleSort: titleSort,
            summary: nil,
            thumb: thumb,
            art: art,
            country: nil,
            genres: nil,
            userRating: nil,
            rating: nil,
            albumCount: nil,
            trackCount: nil,
            addedAt: nil,
            updatedAt: nil
        )
    }
}
