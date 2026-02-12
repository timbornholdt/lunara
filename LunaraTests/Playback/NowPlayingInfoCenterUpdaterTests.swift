import MediaPlayer
import Testing
import UIKit
@testable import Lunara

struct NowPlayingInfoCenterUpdaterTests {
    @Test func updateMapsCoreNowPlayingFields() {
        var capturedInfo: [String: Any]?
        let updater = NowPlayingInfoCenterUpdater { info in
            capturedInfo = info
        }
        let metadata = LockScreenNowPlayingMetadata(
            title: "Track One",
            artist: "Artist One",
            albumTitle: "Album One",
            elapsedTime: 42,
            duration: 180,
            isPlaying: true,
            artworkImage: nil
        )

        updater.update(with: metadata)

        #expect(capturedInfo?[MPMediaItemPropertyTitle] as? String == "Track One")
        #expect(capturedInfo?[MPMediaItemPropertyArtist] as? String == "Artist One")
        #expect(capturedInfo?[MPMediaItemPropertyAlbumTitle] as? String == "Album One")
        #expect(capturedInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 42)
        #expect(capturedInfo?[MPMediaItemPropertyPlaybackDuration] as? Double == 180)
        #expect(capturedInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
    }

    @Test func updateIncludesArtworkWhenProvided() {
        var capturedInfo: [String: Any]?
        let updater = NowPlayingInfoCenterUpdater { info in
            capturedInfo = info
        }
        let metadata = LockScreenNowPlayingMetadata(
            title: "Track One",
            artist: nil,
            albumTitle: nil,
            elapsedTime: 1,
            duration: nil,
            isPlaying: false,
            artworkImage: makeTestImage(color: .red)
        )

        updater.update(with: metadata)

        #expect(capturedInfo?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
        #expect(capturedInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0.0)
    }

    @Test func clearResetsNowPlayingInfo() {
        var capturedInfo: [String: Any]? = [MPMediaItemPropertyTitle: "Track One"]
        let updater = NowPlayingInfoCenterUpdater { info in
            capturedInfo = info
        }

        updater.clear()

        #expect(capturedInfo == nil)
    }
}

private func makeTestImage(color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
}
