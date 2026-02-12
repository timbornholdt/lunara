import MediaPlayer
import UIKit

struct LockScreenNowPlayingMetadata {
    let title: String
    let artist: String?
    let albumTitle: String?
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
    let isPlaying: Bool
    let artworkImage: UIImage?
}

protocol NowPlayingInfoCenterUpdating {
    func update(with metadata: LockScreenNowPlayingMetadata)
    func clear()
}

final class NowPlayingInfoCenterUpdater: NowPlayingInfoCenterUpdating {
    typealias InfoSetter = ([String: Any]?) -> Void

    private let setNowPlayingInfo: InfoSetter

    init(setNowPlayingInfo: @escaping InfoSetter = { MPNowPlayingInfoCenter.default().nowPlayingInfo = $0 }) {
        self.setNowPlayingInfo = setNowPlayingInfo
    }

    func update(with metadata: LockScreenNowPlayingMetadata) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(metadata.elapsedTime, 0),
            MPNowPlayingInfoPropertyPlaybackRate: metadata.isPlaying ? 1.0 : 0.0
        ]

        if let artist = metadata.artist, artist.isEmpty == false {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        if let albumTitle = metadata.albumTitle, albumTitle.isEmpty == false {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let duration = metadata.duration, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artworkImage = metadata.artworkImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in
                artworkImage
            }
        }

        setNowPlayingInfo(nowPlayingInfo)
    }

    func clear() {
        setNowPlayingInfo(nil)
    }
}
