import Foundation
import Testing
@testable import Lunara

@MainActor
struct AlbumDetailViewModelTests {
    @Test func loadsTracksForAlbum() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/test",
            librarySectionID: 1,
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
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [PlexTrack(ratingKey: "1", title: "Track", index: 1, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil)]
        )
        var invalidated = false
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadTracks()

        #expect(viewModel.tracks.count == 1)
        #expect(invalidated == false)
    }

    @Test func mergesTracksAcrossDuplicateAlbumRatingKeys() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/test",
            librarySectionID: 1,
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
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let trackOne = PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil)
        let trackTwo = PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "11", duration: nil, media: nil)
        let trackThree = PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            tracksByAlbumRatingKey: [
                "10": [trackOne, trackThree],
                "11": [trackTwo, trackOne]
            ]
        )
        let viewModel = AlbumDetailViewModel(
            album: album,
            albumRatingKeys: ["10", "11"],
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadTracks()

        #expect(viewModel.tracks.count == 3)
        #expect(viewModel.tracks.map(\.ratingKey) == ["1", "2", "3"])
    }

    @Test func unauthorizedClearsTokenAndInvalidatesSession() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/test",
            librarySectionID: 1,
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
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            error: PlexHTTPError.httpStatus(401, Data())
        )
        var invalidated = false
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadTracks()

        #expect(tokenStore.token == nil)
        #expect(invalidated == true)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
    }

    @Test func playAlbumStartsAtFirstTrack() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/test",
            librarySectionID: 1,
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
        let playback = StubPlaybackController()
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            playbackController: playback,
            cacheStore: InMemoryLibraryCacheStore()
        )
        viewModel.tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil)
        ]

        viewModel.playAlbum()

        #expect(playback.lastStartIndex == 0)
        #expect(playback.lastTracks?.count == 2)
        #expect(playback.lastContext?.album.ratingKey == "10")
    }

    @Test func playTrackStartsAtSelectedIndex() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/test",
            librarySectionID: 1,
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
        let playback = StubPlaybackController()
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            playbackController: playback,
            cacheStore: InMemoryLibraryCacheStore()
        )
        let trackOne = PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil)
        let trackTwo = PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "10", duration: nil, media: nil)
        viewModel.tracks = [trackOne, trackTwo]

        viewModel.playTrack(trackTwo)

        #expect(playback.lastStartIndex == 1)
        #expect(playback.lastContext?.album.ratingKey == "10")
    }

    @Test func refreshDownloadProgressPublishesAlbumProgress() async {
        let album = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/test",
            librarySectionID: 1,
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
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let statusProvider = StubOfflineDownloadStatusProvider(
            progress: OfflineAlbumDownloadProgress(
                albumIdentity: OfflineAlbumIdentity.make(for: album),
                totalTrackCount: 10,
                completedTrackCount: 3,
                pendingTrackCount: 5,
                inProgressTrackCount: 2,
                partialInProgressTrackUnits: 0.5
            )
        )
        let viewModel = AlbumDetailViewModel(
            album: album,
            tokenStore: tokenStore,
            serverStore: serverStore,
            downloadStatusProvider: statusProvider,
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.refreshDownloadProgress()

        #expect(viewModel.albumDownloadProgress?.albumIdentity == OfflineAlbumIdentity.make(for: album))
        let fraction = viewModel.albumDownloadProgress?.fractionComplete ?? -1
        #expect(abs(fraction - 0.35) < 0.0001)
    }
}

private final class StubPlaybackController: PlaybackControlling {
    private(set) var lastTracks: [PlexTrack]?
    private(set) var lastStartIndex: Int?
    private(set) var lastContext: NowPlayingContext?
    private(set) var toggleCallCount = 0

    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
        lastTracks = tracks
        lastStartIndex = startIndex
        lastContext = context
    }

    func togglePlayPause() {
        toggleCallCount += 1
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

private final class StubOfflineDownloadStatusProvider: OfflineDownloadStatusProviding {
    private let progress: OfflineAlbumDownloadProgress?

    init(progress: OfflineAlbumDownloadProgress?) {
        self.progress = progress
    }

    func albumDownloadProgress(albumIdentity: String) async -> OfflineAlbumDownloadProgress? {
        progress
    }
}
