import Foundation

@MainActor
final class ArtworkPipeline: ArtworkPipelineProtocol {
    private let store: LibraryStoreProtocol
    private let session: URLSessionProtocol
    private let fileManager: FileManager
    private let cacheDirectoryURL: URL

    init(
        store: LibraryStoreProtocol,
        session: URLSessionProtocol,
        fileManager: FileManager = .default,
        cacheDirectoryURL: URL
    ) {
        self.store = store
        self.session = session
        self.fileManager = fileManager
        self.cacheDirectoryURL = cacheDirectoryURL
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
        if let cached = try await cachedFileURL(for: key) {
            return cached
        }

        guard let sourceURL else {
            return nil
        }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data, key: key)

            try ensureCacheDirectoryExists()
            let destinationURL = cacheDirectoryURL.appendingPathComponent(fileName(for: key, sourceURL: sourceURL))
            try data.write(to: destinationURL, options: .atomic)
            try await store.setArtworkPath(destinationURL.path, for: key.storeKey)
            return destinationURL
        } catch {
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

        return URL(fileURLWithPath: path)
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
