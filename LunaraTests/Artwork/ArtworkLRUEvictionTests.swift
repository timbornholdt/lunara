import Foundation
import Testing
import UIKit
@testable import Lunara

struct ArtworkLRUEvictionTests {
    @Test func evictsLeastRecentlyUsedEntriesUntilUnderCap() throws {
        let tempURL = try makeTempDirectory()
        let dataA = try makeImageData(color: .red)
        let dataB = try makeImageData(color: .green)
        let dataC = try makeImageData(color: .blue)
        let clock = DateSequence()
        let cache = ArtworkDiskCache(
            rootURL: tempURL,
            maxSizeBytes: dataA.count * 2,
            dateProvider: clock.next
        )
        let keyA = ArtworkCacheKey(ratingKey: "a", artworkPath: "/art/a", size: .grid)
        let keyB = ArtworkCacheKey(ratingKey: "b", artworkPath: "/art/b", size: .grid)
        let keyC = ArtworkCacheKey(ratingKey: "c", artworkPath: "/art/c", size: .grid)

        try cache.store(dataA, for: keyA)
        try cache.store(dataB, for: keyB)
        _ = try cache.imageData(for: keyA)
        try cache.store(dataC, for: keyC)

        #expect(cache.index.totalSizeBytes <= dataA.count * 2)
        #expect(cache.index.entries[keyA.cacheKeyString] != nil)
        #expect(cache.index.entries[keyB.cacheKeyString] == nil || cache.index.entries[keyC.cacheKeyString] == nil)
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

private final class DateSequence {
    private var current = Date(timeIntervalSince1970: 0)

    func next() -> Date {
        defer { current = current.addingTimeInterval(1) }
        return current
    }
}
