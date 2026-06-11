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
}
