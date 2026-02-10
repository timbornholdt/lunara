import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaybackViewModelTests {
    @Test func playDelegatesToEngine() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine)
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        viewModel.play(tracks: tracks, startIndex: 0)

        #expect(engine.playCallCount == 1)
        #expect(engine.lastStartIndex == 0)
        #expect(engine.lastTracks?.count == 1)
    }

    @Test func updatesNowPlayingFromEngineState() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine)
        let state = NowPlayingState(
            trackTitle: "Track",
            artistName: "Artist",
            isPlaying: true,
            trackIndex: 1,
            elapsedTime: 10,
            duration: 120
        )

        engine.emitState(state)

        #expect(viewModel.nowPlaying == state)
    }

    @Test func updatesErrorMessageFromEngine() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine)

        engine.emitError(PlaybackError(message: "Playback failed."))

        #expect(viewModel.errorMessage == "Playback failed.")
    }
}

private final class StubPlaybackEngine: PlaybackEngineing {
    var onStateChange: ((NowPlayingState?) -> Void)?
    var onError: ((PlaybackError) -> Void)?

    private(set) var playCallCount = 0
    private(set) var lastTracks: [PlexTrack]?
    private(set) var lastStartIndex: Int?

    func play(tracks: [PlexTrack], startIndex: Int) {
        playCallCount += 1
        lastTracks = tracks
        lastStartIndex = startIndex
    }

    func stop() {
    }

    func emitState(_ state: NowPlayingState) {
        onStateChange?(state)
    }

    func emitError(_ error: PlaybackError) {
        onError?(error)
    }
}
