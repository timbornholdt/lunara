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
