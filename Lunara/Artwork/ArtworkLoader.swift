import Foundation
import UIKit

protocol ArtworkFetching {
    func fetch(url: URL) async throws -> Data
}

protocol ArtworkPrefetching {
    func prefetch(_ requests: [ArtworkRequest])
}

struct ArtworkRequest: Sendable {
    let key: ArtworkCacheKey
    let url: URL
}

final class ArtworkLoader: ArtworkPrefetching {
    static let shared = ArtworkLoader(
        cache: ArtworkCache(
            memoryCache: ArtworkMemoryCache(),
            diskCache: ArtworkDiskCache(
                rootURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Lunara", isDirectory: true),
                maxSizeBytes: 250 * 1024 * 1024
            )
        ),
        fetcher: URLSessionArtworkFetcher()
    )

    private let cache: ArtworkCache
    private let fetcher: ArtworkFetching

    init(cache: ArtworkCache, fetcher: ArtworkFetching) {
        self.cache = cache
        self.fetcher = fetcher
    }

    func loadImage(for key: ArtworkCacheKey, url: URL) async throws -> UIImage {
        if let cached = try cache.image(for: key) {
            return cached
        }
        let data = try await fetcher.fetch(url: url)
        try cache.store(data, for: key)
        guard let image = UIImage(data: data) else {
            throw ArtworkLoaderError.invalidImageData
        }
        return image
    }

    func prefetch(_ requests: [ArtworkRequest]) {
        guard !requests.isEmpty else { return }
        Task.detached(priority: .utility) { [cache, fetcher] in
            for request in requests {
                if (try? cache.image(for: request.key)) != nil {
                    continue
                }
                let data = try? await fetcher.fetch(url: request.url)
                if let data {
                    try? cache.store(data, for: request.key)
                }
            }
        }
    }
}

enum ArtworkLoaderError: Error {
    case invalidImageData
}

private struct URLSessionArtworkFetcher: ArtworkFetching {
    func fetch(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw PlexHTTPError.httpStatus(http.statusCode, data)
        }
        return data
    }
}
