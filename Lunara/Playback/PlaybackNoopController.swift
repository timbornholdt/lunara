import Foundation

struct PlaybackNoopController: PlaybackControlling {
    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
    }

    func togglePlayPause() {
    }

    func stop() {
    }

    func skipToNext() {
    }

    func skipToPrevious() {
    }

    func seek(to seconds: TimeInterval) {
    }
}
