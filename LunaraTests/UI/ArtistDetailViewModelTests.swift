import Foundation
import Testing
@testable import Lunara

@MainActor
struct ArtistDetailViewModelTests {
    @Test func loadsArtistAndSortsAlbumsByYearAscending() async {
        let artist = PlexArtist(
            ratingKey: "artist",
            title: "Artist",
            titleSort: nil,
            summary: "Bio",
            thumb: nil,
            art: nil,
            country: nil,
            genres: nil,
            userRating: nil,
            rating: nil,
            albumCount: nil,
            trackCount: nil,
            addedAt: nil,
            updatedAt: nil
        )
        let albums = [
            PlexAlbum(
                ratingKey: "b",
                title: "B",
                thumb: nil,
                art: nil,
                year: 2000,
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
            PlexAlbum(
                ratingKey: "a",
                title: "A",
                thumb: nil,
                art: nil,
                year: 1995,
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
            PlexAlbum(
                ratingKey: "c",
                title: "C",
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
            )
        ]
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            artists: [],
            artistDetail: artist,
            albumsByArtistKey: ["artist": albums]
        )
        let viewModel = ArtistDetailViewModel(
            artistRatingKey: "artist",
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in service },
            playbackController: StubPlaybackController(),
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.load()

        #expect(viewModel.artist?.ratingKey == "artist")
        #expect(viewModel.albums.map(\.ratingKey) == ["a", "b", "c"])
    }

    @Test func playAllOrdersTracksByAlbumYearThenIndex() async {
        let artist = PlexArtist(
            ratingKey: "artist",
            title: "Artist",
            titleSort: nil,
            summary: nil,
            thumb: nil,
            art: nil,
            country: nil,
            genres: nil,
            userRating: nil,
            rating: nil,
            albumCount: nil,
            trackCount: nil,
            addedAt: nil,
            updatedAt: nil
        )
        let albumOld = PlexAlbum(
            ratingKey: "old",
            title: "Old",
            thumb: nil,
            art: nil,
            year: 1990,
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
        let albumNew = PlexAlbum(
            ratingKey: "new",
            title: "New",
            thumb: nil,
            art: nil,
            year: 2000,
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
            PlexTrack(ratingKey: "t2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "old", duration: nil, media: nil),
            PlexTrack(ratingKey: "t1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "old", duration: nil, media: nil),
            PlexTrack(ratingKey: "t3", title: "Three", index: 1, parentIndex: nil, parentRatingKey: "new", duration: nil, media: nil)
        ]
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            artists: [],
            artistDetail: artist,
            albumsByArtistKey: ["artist": [albumNew, albumOld]],
            tracksByArtistKey: ["artist": tracks]
        )
        let playback = StubPlaybackController()
        let viewModel = ArtistDetailViewModel(
            artistRatingKey: "artist",
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in service },
            playbackController: playback,
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.load()
        await viewModel.playAll()

        #expect(playback.lastTracks?.map(\.ratingKey) == ["t1", "t2", "t3"])
    }

    @Test func shuffleUsesInjectedShuffleProvider() async {
        let artist = PlexArtist(
            ratingKey: "artist",
            title: "Artist",
            titleSort: nil,
            summary: nil,
            thumb: nil,
            art: nil,
            country: nil,
            genres: nil,
            userRating: nil,
            rating: nil,
            albumCount: nil,
            trackCount: nil,
            addedAt: nil,
            updatedAt: nil
        )
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "a", duration: nil, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: nil, parentRatingKey: "a", duration: nil, media: nil),
            PlexTrack(ratingKey: "3", title: "Three", index: 3, parentIndex: nil, parentRatingKey: "a", duration: nil, media: nil)
        ]
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            artists: [],
            artistDetail: artist,
            albumsByArtistKey: ["artist": []],
            tracksByArtistKey: ["artist": tracks]
        )
        let playback = StubPlaybackController()
        let viewModel = ArtistDetailViewModel(
            artistRatingKey: "artist",
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in service },
            playbackController: playback,
            shuffleProvider: { Array($0.reversed()) },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.load()
        await viewModel.shuffle()

        #expect(playback.lastTracks?.map(\.ratingKey) == ["3", "2", "1"])
    }

    @Test func mergesAppearsOnAlbumsIntoAlbums() async {
        let artist = PlexArtist(
            ratingKey: "artist",
            title: "Artist",
            titleSort: nil,
            summary: nil,
            thumb: nil,
            art: nil,
            country: nil,
            genres: nil,
            userRating: nil,
            rating: nil,
            albumCount: nil,
            trackCount: nil,
            addedAt: nil,
            updatedAt: nil
        )
        let primaryAlbum = PlexAlbum(
            ratingKey: "primary",
            title: "Primary",
            thumb: nil,
            art: nil,
            year: 2000,
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
        let compilation = PlexAlbum(
            ratingKey: "compilation",
            title: "Comp",
            thumb: nil,
            art: nil,
            year: 1999,
            artist: "Various Artists",
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
            PlexTrack(ratingKey: "t1", title: "One", index: 1, parentIndex: nil, parentRatingKey: "primary", duration: nil, media: nil),
            PlexTrack(ratingKey: "t2", title: "Two", index: 1, parentIndex: nil, parentRatingKey: "compilation", duration: nil, media: nil)
        ]
        let compilationTracks = [
            PlexTrack(ratingKey: "c1", title: "Comp One", index: 1, parentIndex: nil, parentRatingKey: "compilation", duration: 90_000, media: nil),
            PlexTrack(ratingKey: "c2", title: "Comp Two", index: 2, parentIndex: nil, parentRatingKey: "compilation", duration: 120_000, media: nil)
        ]
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            artists: [],
            artistDetail: artist,
            albumsByArtistKey: ["artist": [primaryAlbum]],
            tracksByArtistKey: ["artist": tracks],
            albumDetailsByRatingKey: ["compilation": compilation],
            tracksByAlbumRatingKey: ["compilation": compilationTracks]
        )
        let viewModel = ArtistDetailViewModel(
            artistRatingKey: "artist",
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in service },
            playbackController: StubPlaybackController(),
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.load()

        #expect(viewModel.albums.map(\.ratingKey) == ["compilation", "primary"])
        let compilationAlbum = viewModel.albums.first { $0.ratingKey == "compilation" }
        #expect(compilationAlbum?.duration == 210_000)
    }
}

private final class StubPlaybackController: PlaybackControlling {
    private(set) var lastTracks: [PlexTrack]?
    private(set) var lastStartIndex: Int?
    private(set) var lastContext: NowPlayingContext?

    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
        lastTracks = tracks
        lastStartIndex = startIndex
        lastContext = context
    }

    func enqueue(mode: QueueInsertMode, tracks: [PlexTrack], context: NowPlayingContext?) {}
    func togglePlayPause() {}
    func stop() {}
    func skipToNext() {}
    func skipToPrevious() {}
    func seek(to seconds: TimeInterval) {}
}
