import Foundation

final class OfflinePlaybackIndex: LocalPlaybackIndexing {
    private let manifestStore: OfflineManifestStoring
    private let fileStore: OfflineFileStore
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        manifestStore: OfflineManifestStoring = OfflineManifestStore(),
        fileStore: OfflineFileStore = OfflineFileStore(),
        fileManager: FileManager = .default
    ) {
        self.manifestStore = manifestStore
        self.fileStore = fileStore
        self.fileManager = fileManager
    }

    func fileURL(for trackKey: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let loaded = try? manifestStore.load()
        guard
            let manifest = loaded ?? nil,
            let record = manifest.tracks[trackKey],
            record.state == .completed,
            let relativePath = record.relativeFilePath
        else {
            return nil
        }
        if relativePath.lowercased().hasSuffix(".audio") {
            return nil
        }

        let url = fileStore.absoluteURL(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func markPlayed(trackKey: String, at date: Date) {
        lock.lock()
        defer { lock.unlock() }

        let loaded = try? manifestStore.load()
        guard
            var manifest = loaded ?? nil,
            var record = manifest.tracks[trackKey]
        else {
            return
        }
        record.lastPlayedAt = date
        manifest.tracks[trackKey] = record
        try? manifestStore.save(manifest)
    }
}
