import Foundation
import UIKit
import Testing
@testable import Lunara

struct DownsamplingImageLoaderTests {
    /// Writes a solid-color square image of the given pixel size to a temp file and returns its URL.
    private func makeImageFile(pixelSize: CGFloat, color: UIColor = .systemTeal) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pixelSize, height: pixelSize),
            format: format
        )
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        }
        let data = try #require(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsil-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    @Test
    func load_downsamplesLargeImageToTarget() throws {
        let url = try makeImageFile(pixelSize: 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(DownsamplingImageLoader.load(contentsOf: url, maxPixelSize: 100))
        let cg = try #require(image.cgImage)
        #expect(max(cg.width, cg.height) <= 100)
        #expect(max(cg.width, cg.height) < 1024)
    }

    @Test
    func load_returnsNilForBadURL() {
        let url = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString).jpg")
        #expect(DownsamplingImageLoader.load(contentsOf: url, maxPixelSize: 100) == nil)
    }

    @Test
    func load_pointSizeOverloadUsesPointsTimesScale() throws {
        let url = try makeImageFile(pixelSize: 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(
            DownsamplingImageLoader.load(
                contentsOf: url,
                pointSize: CGSize(width: 50, height: 50),
                scale: 2
            )
        )
        let cg = try #require(image.cgImage)
        // 50pt * scale 2 = 100px target.
        #expect(max(cg.width, cg.height) <= 100)
    }
}
