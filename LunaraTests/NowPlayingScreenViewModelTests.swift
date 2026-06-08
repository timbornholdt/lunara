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
        QueueItem(trackID: trackID, streamKey: "/library/metadata/\(trackID)")
    }

    private func makeTrack(id: String, albumID: String) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 1,
            duration: 180
        )
    }

    /// Builds a VM whose library resolves tracks/albums for the given queue track IDs.
    private func makeViewModel(
        queue: NowPlayingQueueMock,
        trackIDs: [String]
    ) -> NowPlayingScreenViewModel {
        let library = ConfigurableLibraryRepoMock()
        for id in trackIDs {
            let albumID = "al-\(id)"
            library.tracksByID[id] = makeTrack(id: id, albumID: albumID)
            library.albumsByID[albumID] = makeAlbum(id: albumID)
        }
        return NowPlayingScreenViewModel(
            queueManager: queue,
            engine: PlaybackEngineMock(),
            library: library,
            artworkPipeline: ArtworkPipelineMock()
        )
    }

    @Test
    func snapshotCacheStaysBoundedToCurrentAndNext() async throws {
        let ids = ["t0", "t1", "t2", "t3", "t4"]
        let queue = NowPlayingQueueMock()
        queue.items = ids.map { makeQueueItem(trackID: $0) }
        queue.currentIndex = 0
        queue.currentItem = queue.items[0]

        let viewModel = makeViewModel(queue: queue, trackIDs: ids)

        for i in 1..<ids.count {
            try await Task.sleep(nanoseconds: 60_000_000)
            queue.currentIndex = i
            queue.currentItem = queue.items[i]
        }
        // Let the final resolve + prefetch + eviction settle.
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(viewModel.snapshotCacheCountForTesting <= 2)
    }

    /// Lunara-rhp: replacing the whole queue (shuffle a new artist) with the SAME
    /// item count while currentIndex stays 0 must still refresh Up Next. The old
    /// (index, count) dedup guard suppressed this, leaving the previous queue's
    /// tracks showing in Up Next until the track advanced.
    @Test
    func upNextRefreshesWhenQueueReplacedWithSameCountAndIndex() async throws {
        let queueA = ["a0", "a1", "a2"]
        let queueB = ["b0", "b1", "b2"]

        let queue = NowPlayingQueueMock()
        queue.items = queueA.map { makeQueueItem(trackID: $0) }
        queue.currentIndex = 0
        queue.currentItem = queue.items[0]

        let viewModel = makeViewModel(queue: queue, trackIDs: queueA + queueB)

        // Up Next resolves to queue A's upcoming tracks (a1, a2).
        await waitUntil { viewModel.upNextItems.map(\.id) == ["a1", "a2"] }
        #expect(viewModel.upNextItems.map(\.id) == ["a1", "a2"])

        // Shuffle a new artist: same count (3), currentIndex stays 0, all-new tracks.
        queue.items = queueB.map { makeQueueItem(trackID: $0) }
        queue.currentItem = queue.items[0]

        // Up Next must follow to queue B's upcoming tracks (b1, b2).
        await waitUntil { viewModel.upNextItems.map(\.id) == ["b1", "b2"] }
        #expect(viewModel.upNextItems.map(\.id) == ["b1", "b2"])
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Lunara-uww.7.6: the full-size Now Playing artwork must be downsample-decoded
    /// (bounded), not a full-resolution decode of the original.
    @Test
    func nowPlayingArtworkIsDownsampled() async throws {
        let bigArtwork = try makeImageFile(pixelSize: 2048)
        defer { try? FileManager.default.removeItem(at: bigArtwork) }

        let queue = NowPlayingQueueMock()
        queue.items = [makeQueueItem(trackID: "t0")]
        queue.currentIndex = 0
        queue.currentItem = queue.items[0]

        let library = ConfigurableLibraryRepoMock()
        library.tracksByID["t0"] = makeTrack(id: "t0", albumID: "al-t0")
        library.albumsByID["al-t0"] = makeAlbum(id: "al-t0")
        let artwork = ArtworkPipelineMock()
        artwork.fullSizeResultByOwnerID["al-t0"] = bigArtwork

        let viewModel = NowPlayingScreenViewModel(
            queueManager: queue, engine: PlaybackEngineMock(),
            library: library, artworkPipeline: artwork
        )

        await waitUntil { viewModel.artworkImage != nil }
        let image = try #require(viewModel.artworkImage)
        let cg = try #require(image.cgImage)
        // Downsampled to ~1024px, far below the 2048px source.
        #expect(max(cg.width, cg.height) <= 1100)
    }

    /// Lunara-uww.7.6: artwork must be applied as soon as it's decoded, WITHOUT
    /// waiting on the (potentially slow) loudness/waveform fetch.
    @Test
    func artworkAppliesBeforeLoudnessResolves() async throws {
        let art = try makeImageFile(pixelSize: 256)
        defer { try? FileManager.default.removeItem(at: art) }

        let queue = NowPlayingQueueMock()
        queue.items = [makeQueueItem(trackID: "t0")]
        queue.currentIndex = 0
        queue.currentItem = queue.items[0]

        let library = ConfigurableLibraryRepoMock()
        library.tracksByID["t0"] = makeTrack(id: "t0", albumID: "al-t0")
        library.albumsByID["al-t0"] = makeAlbum(id: "al-t0")
        library.loudnessByTrackID["t0"] = [0.1, 0.2, 0.3]
        library.gateLoudnessForTrackID = "t0" // hold the waveform fetch open
        let artwork = ArtworkPipelineMock()
        artwork.fullSizeResultByOwnerID["al-t0"] = art

        let viewModel = NowPlayingScreenViewModel(
            queueManager: queue, engine: PlaybackEngineMock(),
            library: library, artworkPipeline: artwork
        )

        // Artwork appears while loudness is still gated; the waveform is not yet set.
        await waitUntil { viewModel.artworkImage != nil }
        #expect(viewModel.artworkImage != nil)
        #expect(viewModel.waveformLevels == nil)

        // Release the waveform fetch; it then populates.
        library.releaseLoudnessGate()
        await waitUntil { viewModel.waveformLevels != nil }
        #expect(viewModel.waveformLevels == [0.1, 0.2, 0.3])
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
