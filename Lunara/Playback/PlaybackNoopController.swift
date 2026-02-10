import Foundation

struct PlaybackNoopController: PlaybackControlling {
    func play(tracks: [PlexTrack], startIndex: Int) {
    }

    func stop() {
    }
}
