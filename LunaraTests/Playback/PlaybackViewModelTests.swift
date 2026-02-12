import Foundation
import Testing
import UIKit
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
        let nowPlayingCenter = RecordingNowPlayingInfoCenter()
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            nowPlayingInfoCenter: nowPlayingCenter,
            remoteCommandCenter: RecordingRemoteCommandCenter(),
            lockScreenArtworkProvider: StubLockScreenArtworkProvider()
        )
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
        #expect(nowPlayingCenter.updates.last?.title == "Track")
        #expect(nowPlayingCenter.updates.last?.artist == "Artist")
        #expect(nowPlayingCenter.updates.last?.elapsedTime == 10)
        #expect(nowPlayingCenter.updates.last?.duration == 120)
    }

    @Test func lockScreenMetadataIncludesArtworkWhenAvailable() async {
        let engine = StubPlaybackEngine()
        let nowPlayingCenter = RecordingNowPlayingInfoCenter()
        let artworkProvider = StubLockScreenArtworkProvider(
            image: makeTestImage(color: .purple)
        )
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            nowPlayingInfoCenter: nowPlayingCenter,
            remoteCommandCenter: RecordingRemoteCommandCenter(),
            lockScreenArtworkProvider: artworkProvider
        )
        let album = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
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
        let track = PlexTrack(
            ratingKey: "t1",
            title: "One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 120_000,
            media: nil
        )
        let artworkRequest = ArtworkRequest(
            key: ArtworkCacheKey(ratingKey: "a1", artworkPath: "/art/1", size: .detail),
            url: URL(string: "https://example.com/1.png")!
        )
        let context = NowPlayingContext(
            album: album,
            albumRatingKeys: ["a1"],
            tracks: [track],
            artworkRequest: artworkRequest
        )
        let state = NowPlayingState(
            trackRatingKey: "t1",
            trackTitle: "One",
            artistName: "Artist",
            isPlaying: true,
            elapsedTime: 10,
            duration: 120
        )

        viewModel.play(tracks: [track], startIndex: 0, context: context)
        engine.emitState(state)
        _ = await waitUntil {
            nowPlayingCenter.updates.last?.artworkImage != nil
        }

        #expect(nowPlayingCenter.updates.last?.albumTitle == "Album One")
        #expect(nowPlayingCenter.updates.last?.artworkImage != nil)
    }

    @Test func lockScreenMetadataOmitsArtworkWhenUnavailable() async {
        let engine = StubPlaybackEngine()
        let nowPlayingCenter = RecordingNowPlayingInfoCenter()
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            nowPlayingInfoCenter: nowPlayingCenter,
            remoteCommandCenter: RecordingRemoteCommandCenter(),
            lockScreenArtworkProvider: StubLockScreenArtworkProvider(image: nil)
        )
        let track = PlexTrack(
            ratingKey: "t1",
            title: "One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 120_000,
            media: nil
        )
        let state = NowPlayingState(
            trackRatingKey: "t1",
            trackTitle: "One",
            artistName: "Artist",
            isPlaying: true,
            elapsedTime: 0,
            duration: 120
        )

        viewModel.play(tracks: [track], startIndex: 0, context: nil)
        engine.emitState(state)
        _ = await waitUntil {
            nowPlayingCenter.updates.isEmpty == false
        }

        #expect(nowPlayingCenter.updates.last?.artworkImage == nil)
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

    @Test func stopClearsLockScreenAndTearsDownRemoteCommands() async {
        let engine = StubPlaybackEngine()
        let nowPlayingCenter = RecordingNowPlayingInfoCenter()
        let remoteCommands = RecordingRemoteCommandCenter()
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            nowPlayingInfoCenter: nowPlayingCenter,
            remoteCommandCenter: remoteCommands,
            lockScreenArtworkProvider: StubLockScreenArtworkProvider()
        )

        engine.emitState(
            NowPlayingState(
                trackRatingKey: "1",
                trackTitle: "Track",
                artistName: "Artist",
                isPlaying: true,
                elapsedTime: 0,
                duration: 100
            )
        )
        _ = await waitUntil { remoteCommands.configureCallCount == 1 }

        viewModel.stop()

        #expect(nowPlayingCenter.clearCallCount == 1)
        #expect(remoteCommands.teardownCallCount == 1)
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

    @Test func stateChangeMarksTrackPlayedAndQueuesOpportunisticDownloads() async {
        let engine = StubPlaybackEngine()
        let offlineIndex = RecordingLocalPlaybackIndex()
        let opportunisticCacher = RecordingOpportunisticCacher()
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            offlinePlaybackIndex: offlineIndex,
            opportunisticCacher: opportunisticCacher
        )
        let tracks = [
            PlexTrack(ratingKey: "t1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "a1", duration: nil, media: nil),
            PlexTrack(ratingKey: "t2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "a1", duration: nil, media: nil),
            PlexTrack(ratingKey: "t3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "a1", duration: nil, media: nil)
        ]
        let album = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
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
        let context = NowPlayingContext(
            album: album,
            albumRatingKeys: ["a1"],
            tracks: tracks,
            artworkRequest: nil
        )

        viewModel.play(tracks: tracks, startIndex: 0, context: context)
        engine.emitState(
            NowPlayingState(
                trackRatingKey: "t1",
                trackTitle: "One",
                artistName: "Artist",
                isPlaying: true,
                elapsedTime: 0,
                duration: nil
            )
        )
        _ = await waitUntil {
            offlineIndex.markPlayedTrackKeys == ["t1"]
                && opportunisticCacher.lastCurrentTrack?.ratingKey == "t1"
                && opportunisticCacher.lastUpcomingTrackKeys == ["t2", "t3"]
        }

        #expect(offlineIndex.markPlayedTrackKeys == ["t1"])
        #expect(opportunisticCacher.lastCurrentTrack?.ratingKey == "t1")
        #expect(opportunisticCacher.lastUpcomingTrackKeys == ["t2", "t3"])
        #expect(opportunisticCacher.lastLimit == 5)

        engine.emitState(
            NowPlayingState(
                trackRatingKey: "t1",
                trackTitle: "One",
                artistName: "Artist",
                isPlaying: true,
                elapsedTime: 10,
                duration: nil
            )
        )
        _ = await waitUntil {
            offlineIndex.markPlayedTrackKeys == ["t1"]
        }

        #expect(offlineIndex.markPlayedTrackKeys == ["t1"])
    }

    @Test func downloadAlbumQueuesExplicitDownload() async {
        let engine = StubPlaybackEngine()
        let queue = RecordingOfflineDownloadQueue()
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            offlineDownloadQueue: queue
        )
        let album = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
            thumb: nil,
            art: nil,
            year: 2001,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: "plex://album/a1",
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

        viewModel.downloadAlbum(album: album, albumRatingKeys: ["a1", "a2"])
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(queue.albumRequests.count == 1)
        #expect(queue.albumRequests.first?.albumIdentity == "plex://album/a1")
        #expect(queue.albumRequests.first?.albumRatingKeys == ["a1", "a2"])
        #expect(queue.albumRequests.first?.source == .explicitAlbum)
    }

    @Test func downloadCollectionQueuesDedupedAlbumGroups() async {
        let engine = StubPlaybackEngine()
        let queue = RecordingOfflineDownloadQueue()
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let albumA1 = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
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
        let albumA2 = PlexAlbum(
            ratingKey: "a2",
            title: "Album One",
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
        let albumB = PlexAlbum(
            ratingKey: "b1",
            title: "Bravo",
            thumb: nil,
            art: nil,
            year: 2002,
            artist: "Band",
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
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            collections: [],
            albumsByCollectionKey: ["c1": [albumA1, albumA2, albumB]]
        )
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            offlineDownloadQueue: queue
        )
        let collection = PlexCollection(ratingKey: "c1", title: "Collection One", thumb: nil, art: nil, updatedAt: nil, key: nil)

        viewModel.downloadCollection(collection: collection, sectionKey: "2")
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(queue.reconciliations.count == 1)
        #expect(queue.reconciliations.first?.collectionKey == "c1")
        #expect(queue.reconciliations.first?.groups.count == 2)
        #expect(queue.reconciliations.first?.groups.contains { $0.albumRatingKeys == ["b1"] } == true)
        #expect(queue.reconciliations.first?.groups.contains { $0.albumRatingKeys.sorted() == ["a1", "a2"] } == true)
    }

    @Test func restoresPausedNowPlayingFromPersistedQueue() async {
        let track = PlexTrack(
            ratingKey: "t1",
            title: "Track One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 90_000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/1/file.mp3")])]
        )
        let album = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
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
        let state = QueueState(
            entries: [
                QueueEntry(
                    track: track,
                    album: album,
                    albumRatingKeys: ["a1"],
                    artworkRequest: nil,
                    isPlayable: true,
                    skipReason: nil
                )
            ],
            currentIndex: 0,
            elapsedTime: 23,
            isPlaying: false
        )
        let queueManager = QueueManager(store: RecordingQueueStateStore(initial: state))
        let engine = StubPlaybackEngine()

        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            queueManager: queueManager
        )

        #expect(viewModel.nowPlaying?.trackRatingKey == "t1")
        #expect(viewModel.nowPlaying?.isPlaying == false)
        #expect(viewModel.nowPlaying?.elapsedTime == 23)
    }

    @Test func restoredQueueSwitchesContextAlbumWhenTrackAdvancesAcrossAlbums() async {
        let trackOne = PlexTrack(
            ratingKey: "t1",
            title: "Track One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 90_000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/1/file.mp3")])]
        )
        let trackTwo = PlexTrack(
            ratingKey: "t2",
            title: "Track Two",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a2",
            duration: 90_000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/2/file.mp3")])]
        )
        let albumOne = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
            thumb: nil,
            art: nil,
            year: 2001,
            artist: "Bonny Light Horseman",
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
            year: 2021,
            artist: "Adele",
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
        let queueState = QueueState(
            entries: [
                QueueEntry(
                    track: trackOne,
                    album: albumOne,
                    albumRatingKeys: ["a1"],
                    artworkRequest: nil,
                    isPlayable: true,
                    skipReason: nil
                ),
                QueueEntry(
                    track: trackTwo,
                    album: albumTwo,
                    albumRatingKeys: ["a2"],
                    artworkRequest: nil,
                    isPlayable: true,
                    skipReason: nil
                )
            ],
            currentIndex: 0,
            elapsedTime: 15,
            isPlaying: true
        )
        let queueManager = QueueManager(store: RecordingQueueStateStore(initial: queueState))
        let engine = StubPlaybackEngine()
        let nowPlayingCenter = RecordingNowPlayingInfoCenter()
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            nowPlayingInfoCenter: nowPlayingCenter,
            remoteCommandCenter: RecordingRemoteCommandCenter(),
            lockScreenArtworkProvider: StubLockScreenArtworkProvider(),
            queueManager: queueManager
        )

        #expect(viewModel.nowPlayingContext?.album.ratingKey == "a1")

        engine.emitState(
            NowPlayingState(
                trackRatingKey: "t2",
                trackTitle: "Track Two",
                artistName: "Adele",
                isPlaying: true,
                elapsedTime: 0,
                duration: 90,
                queueIndex: 1
            )
        )
        let didSwitchAlbum = await waitUntil {
            viewModel.nowPlayingContext?.album.ratingKey == "a2"
        }

        #expect(didSwitchAlbum)
        #expect(viewModel.nowPlayingContext?.album.artist == "Adele")
        #expect(nowPlayingCenter.updates.last?.albumTitle == "Album Two")
    }

    @Test func duplicateQueueInsertShowsPunBanner() async {
        let engine = StubPlaybackEngine()
        let queueManager = QueueManager(store: RecordingQueueStateStore())
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            queueManager: queueManager
        )
        let album = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
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
        let track = PlexTrack(
            ratingKey: "t1",
            title: "Track One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 90_000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/1/file.mp3")])]
        )

        viewModel.enqueueTrack(
            mode: .playNext,
            track: track,
            album: album,
            albumRatingKeys: ["a1"],
            allTracks: [track],
            artworkRequest: nil
        )
        viewModel.enqueueTrack(
            mode: .playNext,
            track: track,
            album: album,
            albumRatingKeys: ["a1"],
            allTracks: [track],
            artworkRequest: nil
        )
        let didSetBanner = await waitUntil {
            viewModel.errorMessage != nil
        }

        #expect(didSetBanner)
        #expect(viewModel.errorMessage == "Queue cue: we heard you already.")
    }

    @Test func enqueueTrackPlayNextRefreshesQueueWithoutRestartingPlayback() async {
        let engine = StubPlaybackEngine()
        let queueManager = QueueManager(store: RecordingQueueStateStore())
        let viewModel = PlaybackViewModel(
            engine: engine,
            themeProvider: StubThemeProvider(),
            queueManager: queueManager
        )

        let album = PlexAlbum(
            ratingKey: "a1",
            title: "Album One",
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
        let trackOne = PlexTrack(
            ratingKey: "t1",
            title: "Track One",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 90_000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/1/file.mp3")])]
        )
        let trackTwo = PlexTrack(
            ratingKey: "t2",
            title: "Track Two",
            index: 2,
            parentIndex: nil,
            parentRatingKey: "a1",
            duration: 90_000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/2/file.mp3")])]
        )
        let context = NowPlayingContext(
            album: album,
            albumRatingKeys: ["a1"],
            tracks: [trackOne],
            artworkRequest: nil
        )

        viewModel.play(tracks: [trackOne], startIndex: 0, context: context)
        engine.emitState(
            NowPlayingState(
                trackRatingKey: "t1",
                trackTitle: "Track One",
                artistName: "Artist",
                isPlaying: true,
                elapsedTime: 12,
                duration: 90,
                queueIndex: 0
            )
        )

        viewModel.enqueueTrack(
            mode: .playNext,
            track: trackTwo,
            album: album,
            albumRatingKeys: ["a1"],
            allTracks: [trackOne, trackTwo],
            artworkRequest: nil
        )

        let didRefresh = await waitUntil {
            engine.refreshQueueCallCount == 1
        }

        #expect(didRefresh)
        #expect(engine.playCallCount == 1)
        #expect(engine.lastRefreshCurrentIndex == 0)
        #expect(engine.lastRefreshTracks?.map(\.ratingKey) == ["t1", "t2"])
    }
}

private final class StubPlaybackEngine: PlaybackEngineing {
    var onStateChange: ((NowPlayingState?) -> Void)?
    var onError: ((PlaybackError) -> Void)?

    private(set) var playCallCount = 0
    private(set) var refreshQueueCallCount = 0
    private(set) var lastRefreshTracks: [PlexTrack]?
    private(set) var lastRefreshCurrentIndex: Int?
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

    func refreshQueue(tracks: [PlexTrack], currentIndex: Int) {
        refreshQueueCallCount += 1
        lastRefreshTracks = tracks
        lastRefreshCurrentIndex = currentIndex
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

private final class RecordingNowPlayingInfoCenter: NowPlayingInfoCenterUpdating {
    private(set) var updates: [LockScreenNowPlayingMetadata] = []
    private(set) var clearCallCount = 0

    func update(with metadata: LockScreenNowPlayingMetadata) {
        updates.append(metadata)
    }

    func clear() {
        clearCallCount += 1
    }
}

private final class RecordingRemoteCommandCenter: RemoteCommandCenterHandling {
    private(set) var configureCallCount = 0
    private(set) var teardownCallCount = 0
    private(set) var handlers: RemoteCommandHandlers?

    func configure(handlers: RemoteCommandHandlers) {
        configureCallCount += 1
        self.handlers = handlers
    }

    func teardown() {
        teardownCallCount += 1
    }
}

private final class StubLockScreenArtworkProvider: LockScreenArtworkProviding {
    let image: UIImage?

    init(image: UIImage? = nil) {
        self.image = image
    }

    func resolveArtwork(for request: ArtworkRequest?) async -> UIImage? {
        image
    }
}

private final class RecordingLocalPlaybackIndex: LocalPlaybackIndexing {
    private(set) var markPlayedTrackKeys: [String] = []

    func fileURL(for trackKey: String) -> URL? {
        nil
    }

    func markPlayed(trackKey: String, at date: Date) {
        markPlayedTrackKeys.append(trackKey)
    }
}

private final class RecordingOpportunisticCacher: OfflineOpportunisticCaching {
    private(set) var lastCurrentTrack: PlexTrack?
    private(set) var lastUpcomingTrackKeys: [String] = []
    private(set) var lastLimit: Int?

    func enqueueOpportunistic(current: PlexTrack, upcoming: [PlexTrack], limit: Int) async {
        lastCurrentTrack = current
        lastUpcomingTrackKeys = upcoming.map(\.ratingKey)
        lastLimit = limit
    }
}

private final class RecordingOfflineDownloadQueue: OfflineDownloadQueuing {
    struct AlbumRequest: Equatable {
        let albumIdentity: String
        let displayTitle: String
        let artistName: String?
        let artworkPath: String?
        let albumRatingKeys: [String]
        let source: OfflineDownloadSource
    }

    struct CollectionUpdate: Equatable {
        let collectionKey: String
        let title: String
        let albumIdentities: [String]
    }

    private(set) var albumRequests: [AlbumRequest] = []
    private(set) var collectionUpdates: [CollectionUpdate] = []
    private(set) var reconciliations: [(collectionKey: String, title: String, groups: [OfflineCollectionAlbumGroup])] = []

    func enqueueAlbumDownload(
        albumIdentity: String,
        displayTitle: String,
        artistName: String?,
        artworkPath: String?,
        albumRatingKeys: [String],
        source: OfflineDownloadSource
    ) async throws {
        albumRequests.append(
            AlbumRequest(
                albumIdentity: albumIdentity,
                displayTitle: displayTitle,
                artistName: artistName,
                artworkPath: artworkPath,
                albumRatingKeys: albumRatingKeys,
                source: source
            )
        )
    }

    func upsertCollectionRecord(
        collectionKey: String,
        title: String,
        albumIdentities: [String]
    ) async throws {
        collectionUpdates.append(
            CollectionUpdate(
                collectionKey: collectionKey,
                title: title,
                albumIdentities: albumIdentities
            )
        )
    }

    func downloadedCollectionKeys() async -> [String] {
        []
    }

    func reconcileCollectionDownload(
        collectionKey: String,
        title: String,
        albumGroups: [OfflineCollectionAlbumGroup]
    ) async throws {
        reconciliations.append((collectionKey: collectionKey, title: title, groups: albumGroups))
    }

    func removeCollectionDownload(collectionKey: String) async throws {
    }
}

private final class RecordingQueueStateStore: QueueStateStoring {
    private var state: QueueState?

    init(initial: QueueState? = nil) {
        state = initial
    }

    func load() throws -> QueueState? {
        state
    }

    func save(_ state: QueueState) throws {
        self.state = state
    }

    func clear() throws {
        state = nil
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
    return condition()
}

private func makeTestImage(color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
}
