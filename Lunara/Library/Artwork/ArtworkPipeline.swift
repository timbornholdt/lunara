import Foundation
import os

@MainActor
final class ArtworkPipeline: ArtworkPipelineProtocol {
    private let store: LibraryStoreProtocol
    private let session: URLSessionProtocol
    private let fileManager: FileManager
    private let cacheDirectoryURL: URL
    private let maxCacheSizeBytes: Int
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "ArtworkPipeline")

    init(
        store: LibraryStoreProtocol,
        session: URLSessionProtocol,
        fileManager: FileManager = .default,
        cacheDirectoryURL: URL,
        maxCacheSizeBytes: Int = 250 * 1024 * 1024
    ) {
        self.store = store
        self.session = session
        self.fileManager = fileManager
        self.cacheDirectoryURL = cacheDirectoryURL
        self.maxCacheSizeBytes = max(0, maxCacheSizeBytes)
    }

    func fetchThumbnail(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? {
        try await fetchArtwork(
            key: ArtworkCacheKey(ownerID: ownerID, ownerKind: ownerKind, imageKind: .thumbnail),
            sourceURL: sourceURL
        )
    }

    func fetchFullSize(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? {
        try await fetchArtwork(
            key: ArtworkCacheKey(ownerID: ownerID, ownerKind: ownerKind, imageKind: .fullSize),
            sourceURL: sourceURL
        )
    }

    func invalidateCache(for key: ArtworkCacheKey) async throws {
        let storeKey = key.storeKey
        if let path = try await store.artworkPath(for: storeKey), fileManager.fileExists(atPath: path) {
            try removeFile(atPath: path)
        }
        try await store.deleteArtworkPath(for: storeKey)
    }

    func invalidateCache(for ownerID: String, ownerKind: ArtworkOwnerKind) async throws {
        try await invalidateCache(for: ArtworkCacheKey(ownerID: ownerID, ownerKind: ownerKind, imageKind: .thumbnail))
        try await invalidateCache(for: ArtworkCacheKey(ownerID: ownerID, ownerKind: ownerKind, imageKind: .fullSize))
    }

    func invalidateAllCache() async throws {
        do {
            if fileManager.fileExists(atPath: cacheDirectoryURL.path) {
                try fileManager.removeItem(at: cacheDirectoryURL)
            }
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw mapToLibraryError(error)
        }
    }

    private func fetchArtwork(key: ArtworkCacheKey, sourceURL: URL?) async throws -> URL? {
        let tag = "\(key.ownerKind.rawValue)/\(key.ownerID)/\(key.imageKind.rawValue)"

        if let cached = try await cachedFileURL(for: key) {
            logger.debug("artwork cache HIT  \(tag, privacy: .public) → \(cached.lastPathComponent, privacy: .public)")
            return cached
        }

        guard let sourceURL else {
            logger.debug("artwork cache MISS \(tag, privacy: .public) — no sourceURL, returning nil")
            return nil
        }

        logger.info("artwork DOWNLOAD  \(tag, privacy: .public) ← \(sourceURL.host ?? sourceURL.absoluteString, privacy: .public)")

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data, key: key)

            try ensureCacheDirectoryExists()
            let destinationURL = cacheDirectoryURL.appendingPathComponent(fileName(for: key, sourceURL: sourceURL))
            try data.write(to: destinationURL, options: .atomic)
            try await store.setArtworkPath(destinationURL.path, for: key.storeKey)
            logger.info("artwork STORED    \(tag, privacy: .public) → \(destinationURL.lastPathComponent, privacy: .public) (\(data.count / 1024, privacy: .public) KB)")
            try enforceCacheLimit()
            return destinationURL
        } catch {
            logger.error("artwork FAILED    \(tag, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw mapToLibraryError(error)
        }
    }

    private func cachedFileURL(for key: ArtworkCacheKey) async throws -> URL? {
        let storeKey = key.storeKey
        guard let path = try await store.artworkPath(for: storeKey) else {
            return nil
        }

        guard fileManager.fileExists(atPath: path) else {
            try await store.deleteArtworkPath(for: storeKey)
            return nil
        }

        let url = URL(fileURLWithPath: path)
        try touchFile(at: url)
        return url
    }

    private func ensureCacheDirectoryExists() throws {
        do {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw mapToLibraryError(error)
        }
    }

    private func removeFile(atPath path: String) throws {
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw mapToLibraryError(error)
        }
    }

    private func touchFile(at url: URL) throws {
        do {
            try fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
        } catch {
            throw mapToLibraryError(error)
        }
    }

    private func enforceCacheLimit() throws {
        do {
            guard maxCacheSizeBytes > 0 else {
                try clearAllFiles(in: cacheDirectoryURL)
                return
            }

            var entries = try cacheEntries()
            var totalBytes = entries.reduce(0) { $0 + $1.size }

            if totalBytes <= maxCacheSizeBytes {
                return
            }

            entries.sort { $0.lastAccessDate < $1.lastAccessDate }

            for entry in entries where totalBytes > maxCacheSizeBytes {
                try fileManager.removeItem(at: entry.url)
                totalBytes -= entry.size
            }
        } catch {
            throw mapToLibraryError(error)
        }
    }

    private func clearAllFiles(in directoryURL: URL) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for child in children {
            let values = try child.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                try fileManager.removeItem(at: child)
            }
        }
    }

    private struct CacheEntry {
        let url: URL
        let size: Int
        let lastAccessDate: Date
    }

    private func cacheEntries() throws -> [CacheEntry] {
        let files = try fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        )

        return try files.compactMap { url in
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
            )
            guard values.isRegularFile == true else {
                return nil
            }

            let size = values.fileSize ?? 0
            let lastAccessDate = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
            return CacheEntry(url: url, size: size, lastAccessDate: lastAccessDate)
        }
    }

    private func fileName(for key: ArtworkCacheKey, sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let sanitizedOwnerID = key.ownerID.replacingOccurrences(of: "/", with: "_")
        return "\(key.ownerKind.rawValue)-\(sanitizedOwnerID)-\(key.imageKind.rawValue).\(ext)"
    }

    private func validate(response: URLResponse, data: Data, key: ArtworkCacheKey) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LibraryError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401:
                throw LibraryError.authExpired
            case 404:
                throw LibraryError.resourceNotFound(type: "artwork", id: key.ownerID)
            case 504:
                throw LibraryError.timeout
            default:
                throw LibraryError.apiError(
                    statusCode: http.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                )
            }
        }

        if data.isEmpty {
            throw LibraryError.invalidResponse
        }
    }

    private func mapToLibraryError(_ error: Error) -> LibraryError {
        if let error = error as? LibraryError {
            return error
        }

        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return .timeout
            }
            return .plexUnreachable
        }

        return .operationFailed(reason: error.localizedDescription)
    }
}

private extension ArtworkCacheKey {
    var storeKey: ArtworkKey {
        ArtworkKey(
            ownerID: ownerID,
            ownerType: ownerKind.storeType,
            variant: imageKind.storeVariant
        )
    }
}

private extension ArtworkOwnerKind {
    var storeType: ArtworkOwnerType {
        switch self {
        case .album:
            return .album
        case .artist:
            return .artist
        case .collection:
            return .collection
        }
    }
}

private extension ArtworkImageKind {
    var storeVariant: ArtworkVariant {
        switch self {
        case .thumbnail:
            return .thumbnail
        case .fullSize:
            return .full
        }
    }
}
