import Foundation
import UIKit
import Testing
@testable import Lunara

/// Lunara-uww.7.3: the shared resolver caches DECODED Up Next thumbnails (not just
/// the file URL), so the same album art is read+downsample-decoded exactly once and
/// reused across rows and window rebuilds — closing the redundant-decode path that
/// 7.1's full-size `artMemo` and 7.2's per-track row reuse left open.
@MainActor
struct NowPlayingResolverArtworkCacheTests {
    /// Writes a solid-color square PNG of `pixelSize` to a temp file and returns its URL.
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
            .appendingPathComponent("nprac-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private func makeQueueItem(trackID: String, albumID: String) -> QueueItem {
        QueueItem(trackID: trackID, streamKey: "/library/metadata/\(trackID)", albumID: albumID)
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

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Memo-level

    @Test
    func thumbnailArtworkReturnsSameDecodedInstanceOnRepeatFetch() async throws {
        let thumbFile = try makeImageFile(pixelSize: 300)
        defer { try? FileManager.default.removeItem(at: thumbFile) }

        let library = ConfigurableLibraryRepoMock()
        let artwork = ArtworkPipelineMock()
        artwork.thumbnailResultByOwnerID["al0"] = thumbFile
        let resolver = NowPlayingResolver(library: library, artwork: artwork)
        let album = makeAlbum(id: "al0")

        let first = await resolver.thumbnailArtwork(for: album)
        let second = await resolver.thumbnailArtwork(for: album)

        let firstImage = try #require(first)
        #expect(second === firstImage, "second fetch re-decoded instead of serving the cache")
        // One fetch+decode total: the second call was served from the in-memory cache.
        #expect(artwork.thumbnailRequests.filter { $0.ownerID == "al0" }.count == 1)
    }

    @Test
    func thumbnailArtworkDoesNotCacheFailedDecode() async throws {
        let library = ConfigurableLibraryRepoMock()
        let artwork = ArtworkPipelineMock()
        // No thumbnail available yet → decode fails (nil).
        let resolver = NowPlayingResolver(library: library, artwork: artwork)
        let album = makeAlbum(id: "al0")

        let first = await resolver.thumbnailArtwork(for: album)
        #expect(first == nil)

        // Art becomes available; a cached nil would defeat this retry.
        let thumbFile = try makeImageFile(pixelSize: 300)
        defer { try? FileManager.default.removeItem(at: thumbFile) }
        artwork.thumbnailResultByOwnerID["al0"] = thumbFile

        let second = await resolver.thumbnailArtwork(for: album)
        #expect(second != nil, "failed decode was cached, blocking the retry")
    }

    // MARK: - Screen-level integration (the gap 7.2 left)

    /// Multiple distinct tracks from the SAME album in one Up Next window must decode
    /// that album's thumbnail exactly once and share the one decoded instance.
    @Test
    func upNextDedupesSameAlbumThumbnailDecodeWithinWindow() async throws {
        let thumbFile = try makeImageFile(pixelSize: 300)
        defer { try? FileManager.default.removeItem(at: thumbFile) }

        let sharedAlbumID = "al-shared"
        let trackIDs = ["t0", "t1", "t2", "t3", "t4", "t5"]

        let library = ConfigurableLibraryRepoMock()
        for id in trackIDs {
            library.tracksByID[id] = makeTrack(id: id, albumID: sharedAlbumID)
        }
        library.albumsByID[sharedAlbumID] = makeAlbum(id: sharedAlbumID)

        let artwork = ArtworkPipelineMock()
        artwork.thumbnailResultByOwnerID[sharedAlbumID] = thumbFile

        let queue = NowPlayingQueueMock()
        queue.items = trackIDs.map { makeQueueItem(trackID: $0, albumID: sharedAlbumID) }
        queue.currentIndex = 0
        queue.currentItem = queue.items[0]

        let resolver = NowPlayingResolver(library: library, artwork: artwork)
        let viewModel = NowPlayingScreenViewModel(
            queueManager: queue,
            engine: PlaybackEngineMock(),
            library: library,
            resolver: resolver
        )

        // Up Next = t1...t5 (current is t0). Wait for all five rows to carry an image.
        await waitUntil {
            viewModel.upNextItems.count == 5 && viewModel.upNextItems.allSatisfy { $0.artworkImage != nil }
        }
        let rows = viewModel.upNextItems
        #expect(rows.count == 5)

        // Exactly one thumbnail fetch+decode for the shared album across all rows.
        #expect(artwork.thumbnailRequests.filter { $0.ownerID == sharedAlbumID }.count == 1)

        // Every row shares the one decoded instance.
        let firstImage = try #require(rows.first?.artworkImage)
        for row in rows {
            #expect(row.artworkImage === firstImage, "row \(row.id) decoded its own copy")
        }
    }
}
