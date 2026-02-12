import Foundation

@MainActor
protocol PlaybackControlling {
    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?)
    func togglePlayPause()
    func stop()
    func skipToNext()
    func skipToPrevious()
    func seek(to seconds: TimeInterval)
}

protocol PlaybackEngineing: AnyObject {
    var onStateChange: ((NowPlayingState?) -> Void)? { get set }
    var onError: ((PlaybackError) -> Void)? { get set }
    func play(tracks: [PlexTrack], startIndex: Int)
    func togglePlayPause()
    func stop()
    func skipToNext()
    func skipToPrevious()
    func seek(to seconds: TimeInterval)
}

protocol PlaybackPlayer: AnyObject {
    var onItemChanged: ((Int) -> Void)? { get set }
    var onItemFailed: ((Int) -> Void)? { get set }
    var onTimeUpdate: ((TimeInterval) -> Void)? { get set }
    var onPlaybackStateChanged: ((Bool) -> Void)? { get set }

    func setQueue(urls: [URL])
    func play()
    func pause()
    func stop()
    func replaceCurrentItem(url: URL)
    func seek(to seconds: TimeInterval)
}

protocol AudioSessionManaging {
    func configureForPlayback() throws
}

protocol PlaybackFallbackURLBuilding {
    func makeTranscodeURL(trackRatingKey: String) -> URL?
    func makeFallbackURL(for track: PlexTrack) -> URL?
}

extension PlaybackFallbackURLBuilding {
    func makeFallbackURL(for track: PlexTrack) -> URL? {
        makeTranscodeURL(trackRatingKey: track.ratingKey)
    }
}

struct NowPlayingState: Equatable {
    let trackRatingKey: String
    let trackTitle: String
    let artistName: String?
    let isPlaying: Bool
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
}

struct PlaybackError: Equatable {
    let message: String
}

struct NowPlayingContext {
    let album: PlexAlbum
    let albumRatingKeys: [String]
    let tracks: [PlexTrack]
    let artworkRequest: ArtworkRequest?
    let albumsByRatingKey: [String: PlexAlbum]?
    let artworkRequestsByAlbumKey: [String: ArtworkRequest]?

    init(
        album: PlexAlbum,
        albumRatingKeys: [String],
        tracks: [PlexTrack],
        artworkRequest: ArtworkRequest?,
        albumsByRatingKey: [String: PlexAlbum]? = nil,
        artworkRequestsByAlbumKey: [String: ArtworkRequest]? = nil
    ) {
        self.album = album
        self.albumRatingKeys = albumRatingKeys
        self.tracks = tracks
        self.artworkRequest = artworkRequest
        self.albumsByRatingKey = albumsByRatingKey
        self.artworkRequestsByAlbumKey = artworkRequestsByAlbumKey
    }
}
