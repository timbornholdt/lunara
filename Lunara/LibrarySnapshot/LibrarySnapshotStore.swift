import Foundation

struct LibrarySnapshot: Codable, Sendable {
    struct Album: Codable, Sendable {
        let ratingKey: String
        let title: String
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

    let albums: [Album]
    let collections: [Collection]
    let musicSectionKey: String?
    let capturedAt: Date

    init(albums: [Album], collections: [Collection], musicSectionKey: String? = nil, capturedAt: Date = Date()) {
        self.albums = albums
        self.collections = collections
        self.musicSectionKey = musicSectionKey
        self.capturedAt = capturedAt
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
            titleSort: nil,
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
