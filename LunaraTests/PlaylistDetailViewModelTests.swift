import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaylistDetailViewModelTests {
    @Test
    func loadIfNeeded_loadsTracks() async {
        let subject = makeSubject()
        subject.library.playlistItemsByPlaylistID["pl-1"] = [
            LibraryPlaylistItemSnapshot(trackID: "t-1", position: 0, playlistItemID: "pi-1"),
            LibraryPlaylistItemSnapshot(trackID: "t-2", position: 1, playlistItemID: "pi-2")
        ]
        subject.library.tracksByID["t-1"] = makeTrack(id: "t-1", title: "Song A")
        subject.library.tracksByID["t-2"] = makeTrack(id: "t-2", title: "Song B")

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.loadingState == .loaded)
        #expect(subject.viewModel.tracks.count == 2)
        #expect(subject.viewModel.tracks[0].title == "Song A")
        #expect(subject.viewModel.tracks[1].title == "Song B")
    }

    @Test
    func loadIfNeeded_skipsUnresolvableTracks() async {
        let subject = makeSubject()
        subject.library.playlistItemsByPlaylistID["pl-1"] = [
            LibraryPlaylistItemSnapshot(trackID: "t-1", position: 0, playlistItemID: "pi-1"),
            LibraryPlaylistItemSnapshot(trackID: "t-missing", position: 1, playlistItemID: "pi-2")
        ]
        subject.library.tracksByID["t-1"] = makeTrack(id: "t-1", title: "Song A")

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.tracks.count == 1)
        #expect(subject.viewModel.tracks[0].title == "Song A")
    }

    @Test
    func isChoppingBlock_returnsTrueForChoppingBlock() async {
        let playlist = Playlist(plexID: "pl-1", title: "Chopping Block", trackCount: 5, updatedAt: nil)
        let subject = makeSubject(playlist: playlist)

        #expect(subject.viewModel.isChoppingBlock == true)
    }

    @Test
    func isChoppingBlock_returnsFalseForOtherPlaylists() async {
        let playlist = Playlist(plexID: "pl-1", title: "Jazz Mix", trackCount: 5, updatedAt: nil)
        let subject = makeSubject(playlist: playlist)

        #expect(subject.viewModel.isChoppingBlock == false)
    }

    @Test
    func keepItem_removesFromPlaylistAndLocalState() async {
        let subject = makeSubject()
        subject.library.playlistItemsByPlaylistID["pl-1"] = [
            LibraryPlaylistItemSnapshot(trackID: "t-1", position: 0, playlistItemID: "pi-1"),
            LibraryPlaylistItemSnapshot(trackID: "t-2", position: 1, playlistItemID: "pi-2")
        ]
        subject.library.tracksByID["t-1"] = makeTrack(id: "t-1", title: "Song A")
        subject.library.tracksByID["t-2"] = makeTrack(id: "t-2", title: "Song B")

        await subject.viewModel.loadIfNeeded()
        await subject.viewModel.keepItem(at: 0)

        #expect(subject.library.removeFromPlaylistRequests.count == 1)
        #expect(subject.library.removeFromPlaylistRequests[0] == ("pl-1", "pi-1"))
        #expect(subject.viewModel.tracks.count == 1)
        #expect(subject.viewModel.tracks[0].title == "Song B")
    }

    @Test
    func removeWithTodo_showsGardenSheet() async {
        let subject = makeSubject()
        subject.library.playlistItemsByPlaylistID["pl-1"] = [
            LibraryPlaylistItemSnapshot(trackID: "t-1", position: 0, playlistItemID: "pi-1")
        ]
        subject.library.tracksByID["t-1"] = makeTrack(id: "t-1", title: "Song A")

        await subject.viewModel.loadIfNeeded()
        subject.viewModel.removeWithTodo(at: 0)

        #expect(subject.viewModel.showGardenSheet == true)
        #expect(subject.viewModel.gardenSheetTrack?.plexID == "t-1")
        #expect(subject.viewModel.gardenSheetPlaylistItemID == "pi-1")
    }

    @Test
    func playAll_delegatesToActions() async {
        let subject = makeSubject()

        await subject.viewModel.playAll()

        #expect(subject.actions.playPlaylistRequests == ["pl-1"])
    }

    @Test
    func shuffle_delegatesToActions() async {
        let subject = makeSubject()

        await subject.viewModel.shuffle()

        #expect(subject.actions.shufflePlaylistRequests == ["pl-1"])
    }

    private func makeSubject(
        playlist: Playlist? = nil
    ) -> (
        viewModel: PlaylistDetailViewModel,
        library: PlaylistDetailRepoMock,
        actions: PlaylistDetailActionsMock
    ) {
        let library = PlaylistDetailRepoMock()
        let actions = PlaylistDetailActionsMock()
        let resolvedPlaylist = playlist ?? Playlist(plexID: "pl-1", title: "Test Playlist", trackCount: 5, updatedAt: nil)
        let viewModel = PlaylistDetailViewModel(
            playlist: resolvedPlaylist,
            library: library,
            artworkPipeline: ArtworkPipelineMock(),
            actions: actions
        )

        return (viewModel, library, actions)
    }

    private func makeTrack(id: String, title: String = "Track") -> Track {
        Track(
            plexID: id,
            albumID: "album-1",
            title: title,
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/parts/\(id)",
            thumbURL: nil
        )
    }
}

@MainActor
private final class PlaylistDetailRepoMock: LibraryRepoProtocol {
    var playlistItemsByPlaylistID: [String: [LibraryPlaylistItemSnapshot]] = [:]
    var tracksByID: [String: Track] = [:]
    var removeFromPlaylistRequests: [(String, String)] = []
    var albumsByID: [String: Album] = [:]

    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] {
        playlistItemsByPlaylistID[playlistID] ?? []
    }

    func track(id: String) async throws -> Track? {
        tracksByID[id]
    }

    func album(id: String) async throws -> Album? {
        albumsByID[id]
    }

    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws {
        removeFromPlaylistRequests.append((playlistID, playlistItemID))
    }

    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }

    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(timeIntervalSince1970: 0), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        guard let rawValue else { return nil }
        return URL(string: rawValue)
    }
}

@MainActor
private final class PlaylistDetailActionsMock: PlaylistsListActionRouting {
    var playPlaylistRequests: [String] = []
    var shufflePlaylistRequests: [String] = []

    func playPlaylist(_ playlist: Playlist) async throws {
        playPlaylistRequests.append(playlist.plexID)
    }
    func shufflePlaylist(_ playlist: Playlist) async throws {
        shufflePlaylistRequests.append(playlist.plexID)
    }
    func playAlbum(_ album: Album) async throws { }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
