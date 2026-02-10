import Foundation
import Testing
@testable import Lunara

@MainActor
struct ArtistsViewModelTests {
    @Test func loadsSnapshotBeforeRefreshingLive() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let snapshotStore = StubSnapshotStore(
            snapshot: LibrarySnapshot(
                albums: [],
                collections: [],
                artists: [
                    .init(
                        ratingKey: "snap",
                        title: "Snapshot Artist",
                        titleSort: "Snapshot Artist",
                        thumb: nil,
                        art: nil
                    )
                ]
            )
        )
        let gate = AsyncGate()
        let service = BlockingArtistService(
            artists: [
                PlexArtist(
                    ratingKey: "live",
                    title: "Live Artist",
                    titleSort: "Live Artist",
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
            ],
            gate: gate
        )
        let viewModel = ArtistsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: snapshotStore
        )

        let task = Task { await viewModel.loadArtists() }
        await gate.waitForStart()

        #expect(viewModel.artists.first?.ratingKey == "snap")
        #expect(viewModel.isRefreshing == true)

        await gate.release()
        await task.value

        #expect(viewModel.artists.first?.ratingKey == "live")
        #expect(viewModel.isRefreshing == false)
        #expect(snapshotStore.savedSnapshot?.artists.first?.ratingKey == "live")
    }

    @Test func sortsArtistsByTitleSortThenTitle() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let service = StubLibraryService(
            sections: [PlexLibrarySection(key: "1", title: "Music", type: "artist")],
            albums: [],
            tracks: [],
            artists: [
                PlexArtist(
                    ratingKey: "1",
                    title: "The National",
                    titleSort: "National",
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
                ),
                PlexArtist(
                    ratingKey: "2",
                    title: "Bon Iver",
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
            ]
        )
        let viewModel = ArtistsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: StubSnapshotStore(snapshot: nil)
        )

        await viewModel.loadArtists()

        #expect(viewModel.artists.map(\.title) == ["Bon Iver", "The National"])
    }

    @Test func filtersArtistsLocally() async {
        let viewModel = ArtistsViewModel(
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in StubLibraryService(sections: [], albums: [], tracks: []) },
            snapshotStore: StubSnapshotStore(snapshot: nil)
        )
        viewModel.artists = [
            PlexArtist(
                ratingKey: "1",
                title: "Radiohead",
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
            ),
            PlexArtist(
                ratingKey: "2",
                title: "Roxy Music",
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
        ]

        let filtered = viewModel.filteredArtists(query: "rad")

        #expect(filtered.map(\.title) == ["Radiohead"])
    }
}

private final class StubSnapshotStore: LibrarySnapshotStoring {
    var snapshot: LibrarySnapshot?
    private(set) var savedSnapshot: LibrarySnapshot?

    init(snapshot: LibrarySnapshot?) {
        self.snapshot = snapshot
    }

    func load() throws -> LibrarySnapshot? {
        snapshot
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        savedSnapshot = snapshot
    }

    func clear() throws {
        snapshot = nil
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func markStarted() {
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitForStart() async {
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }
}

private final class BlockingArtistService: PlexLibraryServicing {
    private let sections: [PlexLibrarySection]
    private let artists: [PlexArtist]
    private let gate: AsyncGate

    init(artists: [PlexArtist], gate: AsyncGate) {
        self.sections = [PlexLibrarySection(key: "1", title: "Music", type: "artist")]
        self.artists = artists
        self.gate = gate
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        return sections
    }

    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] {
        return []
    }

    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack] {
        return []
    }

    func fetchAlbumDetail(albumRatingKey: String) async throws -> PlexAlbum? {
        return nil
    }

    func fetchCollections(sectionId: String) async throws -> [PlexCollection] {
        return []
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        return []
    }

    func fetchArtists(sectionId: String) async throws -> [PlexArtist] {
        await gate.markStarted()
        await gate.wait()
        return artists
    }

    func fetchArtistDetail(artistRatingKey: String) async throws -> PlexArtist? {
        return nil
    }

    func fetchArtistAlbums(artistRatingKey: String) async throws -> [PlexAlbum] {
        return []
    }

    func fetchArtistTracks(artistRatingKey: String) async throws -> [PlexTrack] {
        return []
    }
}
