import Foundation
import Testing
import UIKit
@testable import Lunara

struct ArtworkLoaderTests {
    @Test func returnsCachedImageWithoutFetching() async throws {
        let tempURL = try makeTempDirectory()
        let cache = ArtworkCache(
            memoryCache: ArtworkMemoryCache(),
            diskCache: ArtworkDiskCache(rootURL: tempURL, maxSizeBytes: 1024 * 1024)
        )
        let fetcher = RecordingArtworkFetcher()
        let loader = ArtworkLoader(cache: cache, fetcher: fetcher)
        let key = ArtworkCacheKey(ratingKey: "1", artworkPath: "/art/1", size: .grid)
        let data = try makeImageData(color: .green)
        try cache.store(data, for: key)

        _ = try await loader.loadImage(for: key, url: URL(string: "https://example.com/art/1")!)

        #expect(fetcher.fetchCount == 0)
    }

    @Test func fetchesAndCachesWhenMissing() async throws {
        let tempURL = try makeTempDirectory()
        let cache = ArtworkCache(
            memoryCache: ArtworkMemoryCache(),
            diskCache: ArtworkDiskCache(rootURL: tempURL, maxSizeBytes: 1024 * 1024)
        )
        let imageData = try makeImageData(color: .orange)
        let fetcher = RecordingArtworkFetcher(data: imageData)
        let loader = ArtworkLoader(cache: cache, fetcher: fetcher)
        let key = ArtworkCacheKey(ratingKey: "2", artworkPath: "/art/2", size: .detail)

        _ = try await loader.loadImage(for: key, url: URL(string: "https://example.com/art/2")!)
        let cached = try cache.imageData(for: key)

        #expect(fetcher.fetchCount == 1)
        #expect(cached == imageData)
    }
}

private final class RecordingArtworkFetcher: ArtworkFetching {
    private(set) var fetchCount = 0
    private let data: Data

    init(data: Data = Data(repeating: 1, count: 10)) {
        self.data = data
    }

    func fetch(url: URL) async throws -> Data {
        fetchCount += 1
        return data
    }
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeImageData(color: UIColor) throws -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    guard let data = image.pngData() else {
        throw NSError(domain: "tests.image", code: 1)
    }
    return data
}
