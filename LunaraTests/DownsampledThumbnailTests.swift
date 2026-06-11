import Foundation
import UIKit
import Testing
@testable import Lunara

/// Lunara-gxq: grid/list cells decode local artwork files at display size via
/// DownsamplingImageLoader instead of AsyncImage's full-resolution decode.
struct DownsampledThumbnailTests {
    private func makeImageFile(pixelSize: CGFloat) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pixelSize, height: pixelSize),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        }
        let data = try #require(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dst-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    @Test
    func decode_returnsImageBoundedToMaxPixelSize() async throws {
        let url = try makeImageFile(pixelSize: 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(await DownsampledThumbnail.decode(url: url, maxPixelSize: 540))
        let cg = try #require(image.cgImage)
        #expect(max(cg.width, cg.height) <= 540)
    }

    @Test
    func decode_returnsNilForMissingFile() async {
        let url = URL(fileURLWithPath: "/missing/\(UUID().uuidString).jpg")
        let image = await DownsampledThumbnail.decode(url: url, maxPixelSize: 540)
        #expect(image == nil)
    }

    /// Lunara-inq: re-scrolling the grid must not re-decode from disk — repeat
    /// loads for the same file+size come from the in-memory cache. Proven by
    /// deleting the file between decodes.
    @Test
    func decode_servesRepeatLoadsFromMemoryCache() async throws {
        let url = try makeImageFile(pixelSize: 256)
        let first = try #require(await DownsampledThumbnail.decode(url: url, maxPixelSize: 128))
        try FileManager.default.removeItem(at: url)

        let second = await DownsampledThumbnail.decode(url: url, maxPixelSize: 128)
        #expect(second === first)

        // A different decode size is a different cache entry — no false hit.
        let otherSize = await DownsampledThumbnail.decode(url: url, maxPixelSize: 64)
        #expect(otherSize == nil)
    }
}
