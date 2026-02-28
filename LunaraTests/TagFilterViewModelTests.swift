import Foundation
import Testing
@testable import Lunara

@MainActor
struct TagFilterViewModelTests {
    @Test
    func loadIfNeeded_fetchesAvailableTags() async {
        let subject = makeSubject()
        subject.library.tagsByKind = [
            .genre: ["Electronic", "Rock"],
            .style: ["Ambient"],
            .mood: ["Chill"]
        ]

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.availableGenres == ["Electronic", "Rock"])
        #expect(subject.viewModel.availableStyles == ["Ambient"])
        #expect(subject.viewModel.availableMoods == ["Chill"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadIfNeeded_withInitialGenre_appliesFilterImmediately() async {
        let subject = makeSubject(initialGenres: ["Rock"])
        subject.library.tagsByKind = [.genre: ["Electronic", "Rock"]]
        subject.library.albumsByTagResult["genre:Rock"] = [
            makeAlbum(id: "album-1"),
            makeAlbum(id: "album-2")
        ]

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.albums.count == 2)
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func toggleGenre_addsAndRemoves() async {
        let subject = makeSubject()
        subject.library.tagsByKind = [.genre: ["Rock", "Jazz"]]
        subject.library.albumsByTagResult["genre:Rock"] = [makeAlbum(id: "a1")]
        await subject.viewModel.loadIfNeeded()

        subject.viewModel.toggleGenre("Rock")
        #expect(subject.viewModel.selectedGenres == ["Rock"])

        subject.viewModel.toggleGenre("Rock")
        #expect(subject.viewModel.selectedGenres.isEmpty)
    }

    @Test
    func toggleStyle_addsAndRemoves() async {
        let subject = makeSubject()
        await subject.viewModel.loadIfNeeded()

        subject.viewModel.toggleStyle("Ambient")
        #expect(subject.viewModel.selectedStyles == ["Ambient"])

        subject.viewModel.toggleStyle("Ambient")
        #expect(subject.viewModel.selectedStyles.isEmpty)
    }

    @Test
    func toggleMood_addsAndRemoves() async {
        let subject = makeSubject()
        await subject.viewModel.loadIfNeeded()

        subject.viewModel.toggleMood("Chill")
        #expect(subject.viewModel.selectedMoods == ["Chill"])

        subject.viewModel.toggleMood("Chill")
        #expect(subject.viewModel.selectedMoods.isEmpty)
    }

    @Test
    func filterDescription_showsAllAlbumsWhenNoFilters() {
        let subject = makeSubject()
        #expect(subject.viewModel.filterDescription == "All Albums")
    }

    @Test
    func filterDescription_showsSelectedTags() {
        let subject = makeSubject(initialGenres: ["Rock"])
        #expect(subject.viewModel.filterDescription == "Rock")
    }

    @Test
    func filterDescription_multipleGenres_showsPlusMore() {
        let subject = makeSubject(initialGenres: ["Rock", "Jazz", "Pop"])
        let desc = subject.viewModel.filterDescription
        #expect(desc.contains("+2 more"))
    }

    @Test
    func applyFilter_withNoActiveFilters_clearsAlbums() async {
        let subject = makeSubject()
        await subject.viewModel.loadIfNeeded()

        await subject.viewModel.applyFilter()

        #expect(subject.viewModel.albums.isEmpty)
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func initialTags_arePreselected() {
        let subject = makeSubject(
            initialGenres: ["Rock"],
            initialStyles: ["Grunge"],
            initialMoods: ["Angry"]
        )
        #expect(subject.viewModel.selectedGenres == ["Rock"])
        #expect(subject.viewModel.selectedStyles == ["Grunge"])
        #expect(subject.viewModel.selectedMoods == ["Angry"])
    }

    // MARK: - Helpers

    private struct Subject {
        let viewModel: TagFilterViewModel
        let library: TagFilterRepoMock
        let actions: TagFilterActionsMock
    }

    private func makeSubject(
        initialGenres: Set<String> = [],
        initialStyles: Set<String> = [],
        initialMoods: Set<String> = []
    ) -> Subject {
        let library = TagFilterRepoMock()
        let actions = TagFilterActionsMock()
        let pipeline = TagFilterArtworkPipelineMock()
        let viewModel = TagFilterViewModel(
            library: library,
            artworkPipeline: pipeline,
            actions: actions,
            initialGenres: initialGenres,
            initialStyles: initialStyles,
            initialMoods: initialMoods
        )
        return Subject(viewModel: viewModel, library: library, actions: actions)
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: 2020,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 10,
            duration: 1800
        )
    }
}

@MainActor
private final class TagFilterRepoMock: LibraryRepoProtocol {
    var tagsByKind: [LibraryTagKind: [String]] = [:]
    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]
    var albumsByTagResult: [String: [Album]] = [:]

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        queriedAlbumsByFilter[filter] ?? []
    }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func track(id: String) async throws -> Track? { nil }
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
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func availableTags(kind: LibraryTagKind) async throws -> [String] {
        tagsByKind[kind] ?? []
    }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] {
        albumsByTagResult["\(kind.rawValue):\(value)"] ?? []
    }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(
            reason: reason,
            refreshedAt: Date(timeIntervalSince1970: 0),
            albumCount: 0,
            trackCount: 0,
            artistCount: 0,
            collectionCount: 0
        )
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? { nil }
}

@MainActor
private final class TagFilterActionsMock: TagFilterActionRouting {
    var playAlbumRequests: [String] = []
    var playAlbumsRequests: [[String]] = []
    var shuffleAlbumsRequests: [[String]] = []

    func playAlbum(_ album: Album) async throws {
        playAlbumRequests.append(album.plexID)
    }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
    func playAlbums(_ albums: [Album]) async throws {
        playAlbumsRequests.append(albums.map(\.plexID))
    }
    func shuffleAlbums(_ albums: [Album]) async throws {
        shuffleAlbumsRequests.append(albums.map(\.plexID))
    }
}

@MainActor
private final class TagFilterArtworkPipelineMock: ArtworkPipelineProtocol {
    func fetchThumbnail(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? { nil }
    func fetchFullSize(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? { nil }
    func invalidateCache(for key: ArtworkCacheKey) async throws { }
    func invalidateCache(for ownerID: String, ownerKind: ArtworkOwnerKind) async throws { }
    func invalidateAllCache() async throws { }
}
