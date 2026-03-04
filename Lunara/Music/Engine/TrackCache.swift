import Foundation
import os

actor TrackCache {
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "TrackCache")
    private let cacheDirectory: URL
    private let maxCachedFiles: Int
    private let session: URLSession

    private var cachedFiles: [String: URL] = [:]
    private var accessOrder: [String] = []
    private var activeDownloads: [String: Task<URL, Error>] = [:]

    init(
        cacheDirectory: URL? = nil,
        maxCachedFiles: Int = 5,
        session: URLSession = .shared
    ) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("lunara-track-cache", isDirectory: true)
        self.maxCachedFiles = maxCachedFiles
        self.session = session
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    func prepare(url: URL, trackID: String) async throws -> URL {
        if let existing = cachedFiles[trackID] {
            touchAccessOrder(trackID)
            return existing
        }

        if let existingDownload = activeDownloads[trackID] {
            return try await existingDownload.value
        }

        let downloadTask = Task<URL, Error> {
            let localURL = cacheDirectory.appendingPathComponent("\(trackID).\(url.pathExtension.isEmpty ? "mp3" : url.pathExtension)")

            if url.isFileURL {
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try? FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.copyItem(at: url, to: localURL)
            } else {
                let (tempURL, _) = try await session.download(from: url)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try? FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: localURL)
            }

            return localURL
        }

        activeDownloads[trackID] = downloadTask

        do {
            let localURL = try await downloadTask.value
            activeDownloads[trackID] = nil
            cachedFiles[trackID] = localURL
            touchAccessOrder(trackID)
            evictIfNeeded()
            logger.info("Cached track \(trackID, privacy: .public)")
            return localURL
        } catch {
            activeDownloads[trackID] = nil
            logger.error("Failed to cache track \(trackID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func cachedFile(forTrackID trackID: String) -> URL? {
        cachedFiles[trackID]
    }

    func clearAll() {
        for (_, fileURL) in cachedFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
        cachedFiles.removeAll()
        accessOrder.removeAll()
        for (_, task) in activeDownloads {
            task.cancel()
        }
        activeDownloads.removeAll()
    }

    private func touchAccessOrder(_ trackID: String) {
        accessOrder.removeAll { $0 == trackID }
        accessOrder.append(trackID)
    }

    private func evictIfNeeded() {
        while accessOrder.count > maxCachedFiles {
            let evictID = accessOrder.removeFirst()
            if let fileURL = cachedFiles.removeValue(forKey: evictID) {
                try? FileManager.default.removeItem(at: fileURL)
                logger.info("Evicted cached track \(evictID, privacy: .public)")
            }
        }
    }

}
