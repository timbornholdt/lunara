import Foundation
import Testing
import UIKit
@testable import Lunara

struct ArtworkDiskCacheTests {
    @Test func storesAndLoadsImageDataFromDisk() throws {
        let tempURL = try makeTempDirectory()
        let cache = ArtworkDiskCache(
            rootURL: tempURL,
            maxSizeBytes: 1024 * 1024
        )
        let key = ArtworkCacheKey(ratingKey: "1", artworkPath: "/art/1", size: .grid)
        let data = try makeImageData(color: .red)

        try cache.store(data, for: key)
        let loaded = try cache.imageData(for: key)

        #expect(loaded == data)
    }

    @Test func survivesNewInstanceReload() throws {
        let tempURL = try makeTempDirectory()
        let key = ArtworkCacheKey(ratingKey: "2", artworkPath: "/art/2", size: .detail)
        let data = try makeImageData(color: .blue)
        let cacheA = ArtworkDiskCache(rootURL: tempURL, maxSizeBytes: 1024 * 1024)
        try cacheA.store(data, for: key)

        let cacheB = ArtworkDiskCache(rootURL: tempURL, maxSizeBytes: 1024 * 1024)
        let loaded = try cacheB.imageData(for: key)

        #expect(loaded == data)
    }

    @Test func corruptEntryIsDiscarded() throws {
        let tempURL = try makeTempDirectory()
        let cache = ArtworkDiskCache(rootURL: tempURL, maxSizeBytes: 1024 * 1024)
        let key = ArtworkCacheKey(ratingKey: "3", artworkPath: "/art/3", size: .grid)
        try cache.store(Data(), for: key)

        let loaded = try cache.imageData(for: key)

        #expect(loaded == nil)
        #expect(cache.index.entries[key.cacheKeyString] == nil)
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
