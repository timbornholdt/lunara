import Foundation
import UIKit

struct ArtworkDiskCacheIndex: Codable {
    struct Entry: Codable {
        let fileName: String
        let sizeBytes: Int
        var lastAccess: Date
        let sizeBucket: Int
    }

    var entries: [String: Entry] = [:]
    var totalSizeBytes: Int = 0
}

final class ArtworkDiskCache {
    private let rootURL: URL
    private let fileManager: FileManager
    private let maxSizeBytes: Int
    private let dateProvider: () -> Date
    private let indexURL: URL
    private(set) var index: ArtworkDiskCacheIndex

    init(
        rootURL: URL,
        maxSizeBytes: Int,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.rootURL = rootURL
        self.maxSizeBytes = maxSizeBytes
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.indexURL = rootURL.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.index = ArtworkDiskCache.loadIndex(from: indexURL, fileManager: fileManager)
    }

    func imageData(for key: ArtworkCacheKey) throws -> Data? {
        guard let entry = index.entries[key.cacheKeyString] else {
            return nil
        }
        let fileURL = fileURL(for: key, fileName: entry.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            removeEntry(for: key)
            return nil
        }
        guard UIImage(data: data) != nil else {
            removeEntry(for: key)
            return nil
        }
        updateAccess(for: key)
        return data
    }

    func store(_ data: Data, for key: ArtworkCacheKey) throws {
        let fileURL = fileURL(for: key)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        let sizeBytes = data.count
        recordEntry(sizeBytes: sizeBytes, for: key, fileURL: fileURL, lastAccess: dateProvider())
        try evictIfNeeded()
    }

    func fileURL(for key: ArtworkCacheKey) -> URL {
        let bucket = String(key.size.maxPixelSize)
        return rootURL
            .appendingPathComponent("artwork", isDirectory: true)
            .appendingPathComponent(bucket, isDirectory: true)
            .appendingPathComponent(key.fileName)
    }

    func recordEntry(sizeBytes: Int, for key: ArtworkCacheKey, fileURL: URL, lastAccess: Date) {
        let cacheKey = key.cacheKeyString
        if let existing = index.entries[cacheKey] {
            index.totalSizeBytes -= existing.sizeBytes
        }
        index.entries[cacheKey] = ArtworkDiskCacheIndex.Entry(
            fileName: fileURL.lastPathComponent,
            sizeBytes: sizeBytes,
            lastAccess: lastAccess,
            sizeBucket: key.size.maxPixelSize
        )
        index.totalSizeBytes += sizeBytes
        persistIndex()
    }

    func imageDataExists(for key: ArtworkCacheKey) -> Bool {
        index.entries[key.cacheKeyString] != nil
    }

    private func updateAccess(for key: ArtworkCacheKey) {
        let cacheKey = key.cacheKeyString
        guard var entry = index.entries[cacheKey] else { return }
        entry.lastAccess = dateProvider()
        index.entries[cacheKey] = entry
        persistIndex()
    }

    private func removeEntry(for key: ArtworkCacheKey) {
        let cacheKey = key.cacheKeyString
        guard let entry = index.entries.removeValue(forKey: cacheKey) else { return }
        index.totalSizeBytes -= entry.sizeBytes
        let fileURL = fileURL(for: key, fileName: entry.fileName, sizeBucket: entry.sizeBucket)
        try? fileManager.removeItem(at: fileURL)
        persistIndex()
    }

    private func evictIfNeeded() throws {
        guard index.totalSizeBytes > maxSizeBytes else { return }
        let ordered = index.entries
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
        var currentSize = index.totalSizeBytes
        for (cacheKey, entry) in ordered {
            guard currentSize > maxSizeBytes else { break }
            index.entries.removeValue(forKey: cacheKey)
            currentSize -= entry.sizeBytes
            let fileURL = fileURL(for: cacheKey, entry: entry)
            try? fileManager.removeItem(at: fileURL)
        }
        index.totalSizeBytes = currentSize
        persistIndex()
    }

    private func fileURL(for key: ArtworkCacheKey, fileName: String) -> URL {
        fileURL(for: key, fileName: fileName, sizeBucket: key.size.maxPixelSize)
    }

    private func fileURL(for cacheKey: String, entry: ArtworkDiskCacheIndex.Entry) -> URL {
        rootURL
            .appendingPathComponent("artwork", isDirectory: true)
            .appendingPathComponent(String(entry.sizeBucket), isDirectory: true)
            .appendingPathComponent(entry.fileName)
    }

    private func fileURL(for key: ArtworkCacheKey, fileName: String, sizeBucket: Int) -> URL {
        rootURL
            .appendingPathComponent("artwork", isDirectory: true)
            .appendingPathComponent(String(sizeBucket), isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func persistIndex() {
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("ArtworkDiskCache.persistIndex error: \(error)")
        }
    }

    private static func loadIndex(from url: URL, fileManager: FileManager) -> ArtworkDiskCacheIndex {
        guard let data = try? Data(contentsOf: url) else { return ArtworkDiskCacheIndex() }
        return (try? JSONDecoder().decode(ArtworkDiskCacheIndex.self, from: data)) ?? ArtworkDiskCacheIndex()
    }
}
