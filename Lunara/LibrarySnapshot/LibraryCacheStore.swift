import Foundation

enum LibraryCacheKey {
    case collections
    case artists
    case albums
    case collectionAlbums(String)
    case albumTracks(String)
    case artistDetail(String)
    case artistAlbums(String)

    var stringValue: String {
        switch self {
        case .collections: return "collections"
        case .artists: return "artists"
        case .albums: return "albums"
        case .collectionAlbums(let key): return "collectionAlbums_\(Self.sanitize(key))"
        case .albumTracks(let key): return "albumTracks_\(Self.sanitize(key))"
        case .artistDetail(let key): return "artistDetail_\(Self.sanitize(key))"
        case .artistAlbums(let key): return "artistAlbums_\(Self.sanitize(key))"
        }
    }

    private static func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: ":", with: "_")
           .replacingOccurrences(of: "/", with: "_")
    }
}

protocol LibraryCacheStoring: Sendable {
    func load<T: Decodable>(key: LibraryCacheKey, as type: T.Type) -> T?
    func save<T: Encodable>(key: LibraryCacheKey, value: T)
    func remove(key: LibraryCacheKey)
    func clear()
}

final class LibraryCacheStore: LibraryCacheStoring, @unchecked Sendable {
    private let baseURL: URL
    private let fileManager: FileManager

    init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            self.baseURL = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lunara", isDirectory: true)
                .appendingPathComponent("LibraryCache", isDirectory: true)
        }
        self.fileManager = fileManager
    }

    func load<T: Decodable>(key: LibraryCacheKey, as type: T.Type) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(key: LibraryCacheKey, value: T) {
        do {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            print("LibraryCacheStore.save error key=\(key.stringValue): \(error)")
        }
    }

    func remove(key: LibraryCacheKey) {
        let url = fileURL(for: key)
        try? fileManager.removeItem(at: url)
    }

    func clear() {
        guard fileManager.fileExists(atPath: baseURL.path) else { return }
        try? fileManager.removeItem(at: baseURL)
    }

    private func fileURL(for key: LibraryCacheKey) -> URL {
        baseURL.appendingPathComponent("\(key.stringValue).json")
    }
}
