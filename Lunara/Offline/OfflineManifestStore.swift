import Foundation

final class OfflineManifestStore: OfflineManifestStoring {
    private let baseURL: URL
    private let fileManager: FileManager
    private let manifestURL: URL

    init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseURL {
            self.baseURL = baseURL
        } else {
            self.baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lunara", isDirectory: true)
                .appendingPathComponent("Offline", isDirectory: true)
        }
        self.manifestURL = self.baseURL.appendingPathComponent("offline-manifest.json")
    }

    func load() throws -> OfflineManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        let manifest = try JSONDecoder().decode(OfflineManifest.self, from: data)
        guard manifest.schemaVersion == OfflineManifest.currentSchemaVersion else {
            return nil
        }
        return manifest
    }

    func save(_ manifest: OfflineManifest) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
    }
}
