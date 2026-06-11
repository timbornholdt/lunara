import Foundation
import Testing
@testable import Lunara

@MainActor
struct CollectionDetailViewModelTests {
    @Test
    func loadIfNeeded_fetchesAlbumsForCollectionAndMarksLoaded() async {
        let subject = makeSubject()
        subject.library.collectionAlbumsByID[subject.collection.plexID] = [
            makeAlbum(id: "album-1"),
            makeAlbum(id: "album-2")
        ]

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1", "album-2"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    @Test
    func loadIfNeeded_whenFails_setsErrorState() async {
        let subject = makeSubject()
        subject.library.collectionAlbumsError = .timeout

        await subject.viewModel.loadIfNeeded()

        switch subject.viewModel.loadingState {
        case .error(let message):
            #expect(message == LibraryError.timeout.userMessage)
        default:
            Issue.record("Expected error loading state")
        }
    }

    @Test
    func playAll_routesThroughActions() async {
        let subject = makeSubject()

        await subject.viewModel.playAll()

        #expect(subject.actions.playCollectionRequests == [subject.collection.plexID])
    }

    @Test
    func shuffle_routesThroughActions() async {
        let subject = makeSubject()

        await subject.viewModel.shuffle()

        #expect(subject.actions.shuffleCollectionRequests == [subject.collection.plexID])
    }

    @Test
    func playAll_whenThrows_showsErrorBanner() async {
        let subject = makeSubject()
        subject.actions.playCollectionError = MusicError.trackUnavailable

        await subject.viewModel.playAll()

        #expect(subject.viewModel.errorBannerState.message == MusicError.trackUnavailable.userMessage)
    }

    @Test
    func shuffle_whenThrows_showsErrorBanner() async {
        let subject = makeSubject()
        subject.actions.shuffleCollectionError = MusicError.trackUnavailable

        await subject.viewModel.shuffle()

        #expect(subject.viewModel.errorBannerState.message == MusicError.trackUnavailable.userMessage)
    }

    @Test
    func playAlbum_routesThroughActions() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-play")

        await subject.viewModel.playAlbum(album)

        #expect(subject.actions.playAlbumRequests == ["album-play"])
    }

    // MARK: - Cached-first load + seamless reconcile (Lunara-wd4)

    /// Cached membership renders instantly; the remote reconcile then reflows
    /// the grid in place when Plex's membership differs.
    @Test
    func loadIfNeeded_rendersCacheInstantly_thenReconcilesChanges() async {
        let subject = makeSubject()
        subject.library.collectionAlbumsByID[subject.collection.plexID] = [makeAlbum(id: "album-1")]
        subject.library.refreshedCollectionAlbumsByID[subject.collection.plexID] = [
            makeAlbum(id: "album-1"),
            makeAlbum(id: "album-new")
        ]

        await subject.viewModel.loadIfNeeded()

        // Cache rendered immediately.
        #expect(subject.viewModel.loadingState == .loaded)
        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1"])

        // Background reconcile lands the remote change.
        await waitUntil { subject.viewModel.albums.count == 2 }
        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1", "album-new"])
        #expect(subject.library.refreshRequests == [subject.collection.plexID])
    }

    /// A flaky/empty remote response never blanks a populated page.
    @Test
    func reconcile_ignoresEmptyRemoteMembership() async {
        let subject = makeSubject()
        subject.library.collectionAlbumsByID[subject.collection.plexID] = [makeAlbum(id: "album-1")]
        subject.library.refreshedCollectionAlbumsByID[subject.collection.plexID] = []

        await subject.viewModel.loadIfNeeded()
        await waitUntil { !subject.library.refreshRequests.isEmpty }
        await Task.yield()
        await Task.yield()

        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1"])
    }

    /// Empty cache falls through to the refresh path (which persists membership
    /// for next time), keeping today's first-open behavior.
    @Test
    func loadIfNeeded_withEmptyCache_usesRefreshPath() async {
        let subject = makeSubject()
        subject.library.refreshedCollectionAlbumsByID[subject.collection.plexID] = [makeAlbum(id: "album-1")]

        await subject.viewModel.loadIfNeeded()

        #expect(subject.viewModel.albums.map(\.plexID) == ["album-1"])
        #expect(subject.viewModel.loadingState == .loaded)
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func makeSubject(
        collectionID: String = "col-1",
        collectionTitle: String = "Test Collection"
    ) -> (
        viewModel: CollectionDetailViewModel,
        collection: Collection,
        library: CollectionDetailRepoMock,
        artwork: ArtworkPipelineMock,
        actions: CollectionDetailActionsMock
    ) {
        let collection = Collection(
            plexID: collectionID,
            title: collectionTitle,
            thumbURL: nil,
            summary: "A test collection",
            albumCount: 5,
            updatedAt: nil
        )
        let library = CollectionDetailRepoMock()
        let artwork = ArtworkPipelineMock()
        let actions = CollectionDetailActionsMock()
        let viewModel = CollectionDetailViewModel(
            collection: collection,
            library: library,
            artworkPipeline: artwork,
            actions: actions
        )

        return (viewModel, collection, library, artwork, actions)
    }

    private func makeAlbum(id: String, title: String? = nil) -> Album {
        Album(
            plexID: id,
            title: title ?? "Album \(id)",
            artistName: "Artist",
            year: nil,
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
private final class CollectionDetailRepoMock: LibraryRepoProtocol {
    var collectionAlbumsByID: [String: [Album]] = [:]
    var collectionAlbumsError: LibraryError?

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func collectionAlbums(collectionID: String) async throws -> [Album] {
        if let collectionAlbumsError { throw collectionAlbumsError }
        return collectionAlbumsByID[collectionID] ?? []
    }

    var refreshedCollectionAlbumsByID: [String: [Album]] = [:]
    private(set) var refreshRequests: [String] = []

    func refreshCollectionAlbums(collectionID: String) async throws -> [Album] {
        refreshRequests.append(collectionID)
        if let collectionAlbumsError { throw collectionAlbumsError }
        return refreshedCollectionAlbumsByID[collectionID] ?? collectionAlbumsByID[collectionID] ?? []
    }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func track(id: String) async throws -> Track? { nil }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }
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
private final class CollectionDetailActionsMock: CollectionsListActionRouting {
    var playCollectionRequests: [String] = []
    var shuffleCollectionRequests: [String] = []
    var playAlbumRequests: [String] = []
    var playCollectionError: Error?
    var shuffleCollectionError: Error?

    func playCollection(_ collection: Collection) async throws {
        playCollectionRequests.append(collection.plexID)
        if let playCollectionError { throw playCollectionError }
    }
    func shuffleCollection(_ collection: Collection) async throws {
        shuffleCollectionRequests.append(collection.plexID)
        if let shuffleCollectionError { throw shuffleCollectionError }
    }
    func playAlbum(_ album: Album) async throws {
        playAlbumRequests.append(album.plexID)
    }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
