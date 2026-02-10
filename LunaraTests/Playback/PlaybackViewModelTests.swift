import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaybackViewModelTests {
    @Test func playDelegatesToEngine() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: StubThemeProvider())
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]

        viewModel.play(tracks: tracks, startIndex: 0, context: nil)

        #expect(engine.playCallCount == 1)
        #expect(engine.lastStartIndex == 0)
        #expect(engine.lastTracks?.count == 1)
    }

    @Test func updatesNowPlayingFromEngineState() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: StubThemeProvider())
        let state = NowPlayingState(
            trackRatingKey: "1",
            trackTitle: "Track",
            artistName: "Artist",
            isPlaying: true,
            elapsedTime: 10,
            duration: 120
        )

        engine.emitState(state)
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.nowPlaying == state)
    }

    @Test func updatesErrorMessageFromEngine() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: StubThemeProvider())

        engine.emitError(PlaybackError(message: "Playback failed."))

        #expect(viewModel.errorMessage == "Playback failed.")
    }

    @Test func togglePlayPauseDelegatesToEngine() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: StubThemeProvider())

        viewModel.togglePlayPause()

        #expect(engine.toggleCallCount == 1)
    }

    @Test func playStoresContextAndRequestsThemeOncePerAlbum() async {
        let engine = StubPlaybackEngine()
        let themeProvider = StubThemeProvider()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: themeProvider)
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: 1000, media: nil)
        ]
        let request = ArtworkRequest(
            key: ArtworkCacheKey(ratingKey: "10", artworkPath: "/art", size: .detail),
            url: URL(string: "https://example.com/art.png")!
        )
        let context = NowPlayingContext(
            album: PlexAlbum(
                ratingKey: "10",
                title: "Album",
                thumb: nil,
                art: nil,
                year: nil,
                artist: "Artist",
                titleSort: nil,
                originalTitle: nil,
                editionTitle: nil,
                guid: nil,
                librarySectionID: nil,
                parentRatingKey: nil,
                studio: nil,
                summary: nil,
                genres: nil,
                styles: nil,
                moods: nil,
                rating: nil,
                userRating: nil,
                key: nil
            ),
            albumRatingKeys: ["10"],
            tracks: tracks,
            artworkRequest: request
        )

        viewModel.play(tracks: tracks, startIndex: 0, context: context)
        viewModel.play(tracks: tracks, startIndex: 0, context: context)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.nowPlayingContext?.album.ratingKey == "10")
        #expect(themeProvider.themeRequestCount == 1)
    }

    @Test func skipAndSeekDelegateToEngine() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: StubThemeProvider())

        viewModel.skipToNext()
        viewModel.skipToPrevious()
        viewModel.seek(to: 42)

        #expect(engine.skipNextCallCount == 1)
        #expect(engine.skipPreviousCallCount == 1)
        #expect(engine.seekCallCount == 1)
    }

    @Test func updatesContextAlbumWhenTrackChanges() async {
        let engine = StubPlaybackEngine()
        let viewModel = PlaybackViewModel(engine: engine, themeProvider: StubThemeProvider())
        let albumOne = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
            thumb: nil,
            art: nil,
            year: 1999,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
            librarySectionID: nil,
            parentRatingKey: nil,
            studio: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let albumTwo = PlexAlbum(
            ratingKey: "a2",
            title: "Album Two",
            thumb: nil,
            art: nil,
            year: 2001,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
            librarySectionID: nil,
            parentRatingKey: nil,
            studio: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let tracks = [
            PlexTrack(ratingKey: "t1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "a1", duration: nil, media: nil),
            PlexTrack(ratingKey: "t2", title: "Two", index: 1, parentIndex: nil, parentRatingKey: "a2", duration: nil, media: nil)
        ]
        let requestOne = ArtworkRequest(
            key: ArtworkCacheKey(ratingKey: "a1", artworkPath: "/art/1", size: .detail),
            url: URL(string: "https://example.com/1.png")!
        )
        let requestTwo = ArtworkRequest(
            key: ArtworkCacheKey(ratingKey: "a2", artworkPath: "/art/2", size: .detail),
            url: URL(string: "https://example.com/2.png")!
        )
        let context = NowPlayingContext(
            album: albumOne,
            albumRatingKeys: ["a1"],
            tracks: tracks,
            artworkRequest: requestOne,
            albumsByRatingKey: ["a1": albumOne, "a2": albumTwo],
            artworkRequestsByAlbumKey: ["a1": requestOne, "a2": requestTwo]
        )

        viewModel.play(tracks: tracks, startIndex: 0, context: context)
        engine.emitState(
            NowPlayingState(
                trackRatingKey: "t2",
                trackTitle: "Two",
                artistName: "Artist",
                isPlaying: true,
                elapsedTime: 0,
                duration: 100
            )
        )
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(viewModel.nowPlayingContext?.album.ratingKey == "a2")
    }
}

private final class StubPlaybackEngine: PlaybackEngineing {
    var onStateChange: ((NowPlayingState?) -> Void)?
    var onError: ((PlaybackError) -> Void)?

    private(set) var playCallCount = 0
    private(set) var toggleCallCount = 0
    private(set) var lastTracks: [PlexTrack]?
    private(set) var lastStartIndex: Int?
    private(set) var skipNextCallCount = 0
    private(set) var skipPreviousCallCount = 0
    private(set) var seekCallCount = 0

    func play(tracks: [PlexTrack], startIndex: Int) {
        playCallCount += 1
        lastTracks = tracks
        lastStartIndex = startIndex
    }

    func stop() {
    }

    func togglePlayPause() {
        toggleCallCount += 1
    }

    func skipToNext() {
        skipNextCallCount += 1
    }

    func skipToPrevious() {
        skipPreviousCallCount += 1
    }

    func seek(to seconds: TimeInterval) {
        seekCallCount += 1
    }

    func emitState(_ state: NowPlayingState) {
        onStateChange?(state)
    }

    func emitError(_ error: PlaybackError) {
        onError?(error)
    }
}

private final class StubThemeProvider: ArtworkThemeProviding {
    private(set) var themeRequestCount = 0

    func theme(for request: ArtworkRequest?) async -> AlbumTheme? {
        guard request != nil else { return nil }
        themeRequestCount += 1
        return AlbumTheme.fallback()
    }
}
