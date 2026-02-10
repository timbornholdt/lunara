import Foundation

@MainActor
protocol PlaybackControlling {
    func play(tracks: [PlexTrack], startIndex: Int)
    func stop()
}

protocol PlaybackEngineing: AnyObject {
    var onStateChange: ((NowPlayingState?) -> Void)? { get set }
    var onError: ((PlaybackError) -> Void)? { get set }
    func play(tracks: [PlexTrack], startIndex: Int)
    func stop()
}

protocol PlaybackPlayer: AnyObject {
    var onItemChanged: ((Int) -> Void)? { get set }
    var onItemFailed: ((Int) -> Void)? { get set }
    var onTimeUpdate: ((TimeInterval) -> Void)? { get set }
    var onPlaybackStateChanged: ((Bool) -> Void)? { get set }

    func setQueue(urls: [URL])
    func play()
    func stop()
    func replaceCurrentItem(url: URL)
}

protocol AudioSessionManaging {
    func configureForPlayback() throws
}

protocol PlaybackFallbackURLBuilding {
    func makeTranscodeURL(trackRatingKey: String) -> URL?
}

struct NowPlayingState: Equatable {
    let trackTitle: String
    let artistName: String?
    let isPlaying: Bool
    let trackIndex: Int
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
}

struct PlaybackError: Equatable {
    let message: String
}
