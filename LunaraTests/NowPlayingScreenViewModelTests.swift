import Foundation
import UIKit
import Testing
@testable import Lunara

@MainActor
struct NowPlayingScreenViewModelTests {
    /// Writes a solid-color square PNG of `pixelSize` to a temp file and returns its URL.
    private func makeImageFile(pixelSize: CGFloat) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pixelSize, height: pixelSize),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        }
        let data = try #require(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("npsvm-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private func makeQueueItem(trackID: String) -> QueueItem {
        QueueItem(trackID: trackID, url: URL(fileURLWithPath: "/tmp/\(trackID).m4a"))
    }

    @Test
    func upNextArtworkIsDownsampledToThumbnailSize() async throws {
        let bigArtwork = try makeImageFile(pixelSize: 1024)
        defer { try? FileManager.default.removeItem(at: bigArtwork) }

        let queue = NowPlayingQueueMock()
        queue.items = [makeQueueItem(trackID: "current"), makeQueueItem(trackID: "next")]
        queue.currentIndex = 0

        let engine = PlaybackEngineMock()
        let library = ConfigurableLibraryRepoMock()
        let artwork = ArtworkPipelineMock()
        // track(id:) returns nil -> up-next loop keys the thumbnail by trackID.
        artwork.thumbnailResultByOwnerID["next"] = bigArtwork

        let viewModel = NowPlayingScreenViewModel(
            queueManager: queue,
            engine: engine,
            library: library,
            artworkPipeline: artwork
        )

        // Poll until the up-next item resolves its artwork (async task in init).
        var resolved: UIImage?
        for _ in 0..<300 {
            if let image = viewModel.upNextItems.first(where: { $0.id == "next" })?.artworkImage {
                resolved = image
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let image = try #require(resolved, "up-next artwork never resolved")
        let cg = try #require(image.cgImage)
        // 40pt row * scale 3 = 120px; far below the 1024px source.
        #expect(max(cg.width, cg.height) <= 130)
    }
}
