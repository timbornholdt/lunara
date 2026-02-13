import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaybackEngineTests {
    @Test func playBuildsQueueStartingAtTrack() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!,
            "2": URL(string: "https://example.com/2.mp3")!,
            "3": URL(string: "https://example.com/3.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 2000, media: nil),
            PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "10", duration: 3000, media: nil)
        ]
        var latestState: NowPlayingState?
        engine.onStateChange = { latestState = $0 }

        engine.play(tracks: tracks, startIndex: 1)

        #expect(player.setQueueURLs == [
            URL(string: "https://example.com/2.mp3")!,
            URL(string: "https://example.com/3.mp3")!
        ])
        #expect(player.playCallCount == 1)
        #expect(audioSession.configureCallCount == 1)
        #expect(latestState?.trackTitle == "Two")
        #expect(latestState?.trackRatingKey == "2")
        #expect(latestState?.duration == 2.0)
        #expect(latestState?.isPlaying == true)
    }

    @Test func startIndexOutOfRangeClampsToZero() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!,
            "2": URL(string: "https://example.com/2.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 2000, media: nil)
        ]

        engine.play(tracks: tracks, startIndex: 9)

        #expect(player.setQueueURLs.count == 2)
    }

    @Test func startIndexSkipsUnavailableTracksAndStartsAtNextPlayable() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!,
            "3": URL(string: "https://example.com/3.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 2000, media: nil),
            PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "10", duration: 3000, media: nil)
        ]
        var latestState: NowPlayingState?
        engine.onStateChange = { latestState = $0 }

        engine.play(tracks: tracks, startIndex: 1)

        #expect(player.setQueueURLs == [URL(string: "https://example.com/3.mp3")!])
        #expect(latestState?.trackRatingKey == "3")
    }

    @Test func failureRebuildsQueueWithFallbackURL() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        engine.play(tracks: tracks, startIndex: 0)
        player.emitFailure(index: 0)

        #expect(player.setQueueURLs == [URL(string: "https://example.com/fallback.m3u8")!])
        #expect(player.playCallCount == 2)
    }

    @Test func localSourceFailureFallsBackToRemoteStream() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(
            urls: ["1": URL(fileURLWithPath: "/tmp/offline-track.audio")],
            localTrackKeys: ["1"]
        )
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        engine.play(tracks: tracks, startIndex: 0)
        player.emitFailure(index: 0)

        #expect(player.setQueueURLs == [URL(string: "https://example.com/fallback.m3u8")!])
        #expect(player.playCallCount == 2)
    }

    @Test func secondFailureEmitsError() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]
        var errorMessage: String?
        engine.onError = { errorMessage = $0.message }

        engine.play(tracks: tracks, startIndex: 0)
        player.emitFailure(index: 0)
        player.emitFailure(index: 0)

        #expect(errorMessage == "Playback failed.")
    }

    @Test func missingPlaybackSourcesEmitsError() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [:])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]
        var errorMessage: String?
        engine.onError = { errorMessage = $0.message }

        engine.play(tracks: tracks, startIndex: 0)

        #expect(errorMessage == "Playback unavailable for this track.")
        #expect(player.setQueueURLs.isEmpty)
    }

    @Test func timeUpdatesFlowIntoState() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]
        var latestState: NowPlayingState?
        engine.onStateChange = { latestState = $0 }

        engine.play(tracks: tracks, startIndex: 0)
        player.emitTimeUpdate(12)

        #expect(latestState?.elapsedTime == 12)
    }

    @Test func stopClearsState() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]
        var latestState: NowPlayingState?
        engine.onStateChange = { latestState = $0 }

        engine.play(tracks: tracks, startIndex: 0)
        engine.stop()

        #expect(player.stopCallCount == 1)
        #expect(latestState == nil)
    }

    @Test func skipToNextRebuildsQueue() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!,
            "2": URL(string: "https://example.com/2.mp3")!,
            "3": URL(string: "https://example.com/3.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 2000, media: nil),
            PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "10", duration: 3000, media: nil)
        ]
        var latestState: NowPlayingState?
        engine.onStateChange = { latestState = $0 }

        engine.play(tracks: tracks, startIndex: 0)
        engine.skipToNext()

        #expect(player.setQueueURLs == [
            URL(string: "https://example.com/2.mp3")!,
            URL(string: "https://example.com/3.mp3")!
        ])
        #expect(latestState?.trackTitle == "Two")
    }

    @Test func skipToPreviousRebuildsQueue() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!,
            "2": URL(string: "https://example.com/2.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 2000, media: nil)
        ]
        var latestState: NowPlayingState?
        engine.onStateChange = { latestState = $0 }

        engine.play(tracks: tracks, startIndex: 1)
        engine.skipToPrevious()

        #expect(player.setQueueURLs == [
            URL(string: "https://example.com/1.mp3")!,
            URL(string: "https://example.com/2.mp3")!
        ])
        #expect(latestState?.trackTitle == "One")
    }

    @Test func seekDelegatesToPlayer() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        engine.play(tracks: tracks, startIndex: 0)
        engine.seek(to: 42)

        #expect(player.lastSeekTime == 42)
    }

    @Test func togglePlayPausePausesWhenPlaying() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        engine.play(tracks: tracks, startIndex: 0)
        engine.togglePlayPause()

        #expect(player.pauseCallCount == 1)
    }

    @Test func togglePlayPauseResumesWhenPaused() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        engine.play(tracks: tracks, startIndex: 0)
        engine.togglePlayPause()
        engine.togglePlayPause()

        #expect(player.pauseCallCount == 1)
        #expect(player.playCallCount == 2)
    }

    @Test func refreshQueueReplacesUpcomingWithoutRestartingCurrentTrack() async throws {
        let player = TestPlaybackPlayer()
        let resolver = StubPlaybackSourceResolver(urls: [
            "1": URL(string: "https://example.com/1.mp3")!,
            "2": URL(string: "https://example.com/2.mp3")!,
            "3": URL(string: "https://example.com/3.mp3")!
        ])
        let fallbackBuilder = StubFallbackURLBuilder(url: URL(string: "https://example.com/fallback.m3u8")!)
        let audioSession = StubAudioSessionManager()
        let engine = PlaybackEngine(
            player: player,
            sourceResolver: resolver,
            fallbackURLBuilder: fallbackBuilder,
            audioSession: audioSession
        )
        let initial = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: 2000, media: nil)
        ]
        let updated = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil),
            PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "10", duration: 3000, media: nil)
        ]

        engine.play(tracks: initial, startIndex: 0)
        engine.refreshQueue(tracks: updated, currentIndex: 0)

        #expect(player.playCallCount == 1)
        #expect(player.replaceUpcomingURLs == [URL(string: "https://example.com/3.mp3")!])
    }
}

private final class TestPlaybackPlayer: PlaybackPlayer {
    var onItemChanged: ((Int) -> Void)?
    var onItemFailed: ((Int) -> Void)?
    var onTimeUpdate: ((TimeInterval) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private(set) var setQueueURLs: [URL] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var replacedCurrentItemURL: URL?
    private(set) var replaceUpcomingURLs: [URL] = []
    private(set) var lastSeekTime: TimeInterval?

    func setQueue(urls: [URL]) {
        setQueueURLs = urls
        onItemChanged?(0)
    }

    func play() {
        playCallCount += 1
        onPlaybackStateChanged?(true)
    }

    func pause() {
        pauseCallCount += 1
        onPlaybackStateChanged?(false)
    }

    func stop() {
        stopCallCount += 1
        onPlaybackStateChanged?(false)
    }

    func replaceCurrentItem(url: URL) {
        replacedCurrentItemURL = url
    }

    func replaceUpcoming(urls: [URL]) {
        replaceUpcomingURLs = urls
    }

    func seek(to seconds: TimeInterval) {
        lastSeekTime = seconds
    }

    func emitFailure(index: Int) {
        onItemFailed?(index)
    }

    func emitTimeUpdate(_ time: TimeInterval) {
        onTimeUpdate?(time)
    }
}

private struct StubPlaybackSourceResolver: PlaybackSourceResolving {
    let urls: [String: URL]
    let localTrackKeys: Set<String>

    init(urls: [String: URL], localTrackKeys: Set<String> = []) {
        self.urls = urls
        self.localTrackKeys = localTrackKeys
    }

    func resolveSource(for track: PlexTrack) -> PlaybackSource? {
        guard let url = urls[track.ratingKey] else { return nil }
        if localTrackKeys.contains(track.ratingKey) {
            return .local(fileURL: url)
        }
        return .remote(url: url)
    }
}

private struct StubFallbackURLBuilder: PlaybackFallbackURLBuilding {
    let url: URL

    func makeTranscodeURL(trackRatingKey: String) -> URL? {
        url
    }
}

private final class StubAudioSessionManager: AudioSessionManaging {
    private(set) var configureCallCount = 0

    func configureForPlayback() throws {
        configureCallCount += 1
    }
}
