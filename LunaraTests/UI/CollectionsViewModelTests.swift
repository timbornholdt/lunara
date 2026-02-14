import Foundation
import Testing
@testable import Lunara

@MainActor
struct CollectionsViewModelTests {
    @Test func loadsCollectionsFromFirstMusicSectionAndLogsTitles() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [
            PlexLibrarySection(key: "1", title: "Movies", type: "movie"),
            PlexLibrarySection(key: "2", title: "Music", type: "artist")
        ]
        let collections = [
            PlexCollection(ratingKey: "100", title: "Zed", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "101", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        ]
        let service = RecordingLibraryService(
            sections: sections,
            collections: collections
        )
        var loggedTitles: [String] = []
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            logger: { loggedTitles = $0 },
            snapshotStore: StubSnapshotStore(snapshot: nil),
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadCollections()

        #expect(service.lastCollectionsSectionId == "2")
        #expect(viewModel.collections.count == 2)
        #expect(loggedTitles == ["Zed", "Current Vibes"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func ordersPinnedCollectionsFirstThenAlphabetical() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "2", title: "Music", type: "artist")]
        let collections = [
            PlexCollection(ratingKey: "1", title: "Zed", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "2", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "3", title: "Alpha", thumb: nil, art: nil, updatedAt: nil, key: nil),
            PlexCollection(ratingKey: "4", title: "The Key Albums", thumb: nil, art: nil, updatedAt: nil, key: nil)
        ]
        let service = RecordingLibraryService(sections: sections, collections: collections)
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: StubSnapshotStore(snapshot: nil),
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadCollections()

        #expect(viewModel.collections.map(\.title) == [
            "Current Vibes",
            "The Key Albums",
            "Alpha",
            "Zed"
        ])
    }

    @Test func identifiesPinnedCollections() {
        let viewModel = CollectionsViewModel(
            tokenStore: InMemoryTokenStore(token: "token"),
            serverStore: InMemoryServerStore(url: URL(string: "https://example.com:32400")!),
            libraryServiceFactory: { _, _ in RecordingLibraryService(sections: [], collections: []) },
            cacheStore: InMemoryLibraryCacheStore()
        )
        let pinned = PlexCollection(ratingKey: "1", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let normal = PlexCollection(ratingKey: "2", title: "Other", thumb: nil, art: nil, updatedAt: nil, key: nil)

        #expect(viewModel.isPinned(pinned))
        #expect(viewModel.isPinned(normal) == false)
    }

    @Test func noMusicSectionSetsError() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "1", title: "Movies", type: "movie")]
        let service = RecordingLibraryService(sections: sections, collections: [])
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: StubSnapshotStore(snapshot: nil),
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadCollections()

        #expect(viewModel.collections.isEmpty)
        #expect(viewModel.errorMessage == "No music library found.")
    }

    @Test func loadsSnapshotBeforeRefreshingLive() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let snapshotStore = StubSnapshotStore(
            snapshot: LibrarySnapshot(
                albums: [],
                collections: [
                    .init(
                        ratingKey: "snap",
                        title: "Snapshot Collection",
                        thumb: "/thumb/snap",
                        art: "/art/snap"
                    )
                ]
            )
        )
        let gate = AsyncGate()
        let service = BlockingCollectionsService(
            sections: [PlexLibrarySection(key: "2", title: "Music", type: "music")],
            collections: [PlexCollection(ratingKey: "live", title: "Live Collection", thumb: nil, art: nil, updatedAt: nil, key: nil)],
            gate: gate
        )
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: snapshotStore,
            cacheStore: InMemoryLibraryCacheStore(),
            artworkPrefetcher: NoopArtworkPrefetcher()
        )

        // Load snapshot first (returns immediately from snapshot)
        await viewModel.loadCollections()
        #expect(viewModel.collections.first?.ratingKey == "snap")

        // Then refresh triggers network fetch
        let task = Task { await viewModel.refresh() }
        await gate.waitForStart()

        #expect(viewModel.isRefreshing == true)

        await gate.release()
        await task.value

        #expect(viewModel.collections.first?.ratingKey == "live")
        #expect(viewModel.isRefreshing == false)
        #expect(snapshotStore.savedSnapshot?.collections.first?.ratingKey == "live")
    }

    @Test func refreshReconcilesDownloadedCollections() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "2", title: "Music", type: "artist")]
        let collection = PlexCollection(ratingKey: "c1", title: "Collection One", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let albumA1 = PlexAlbum(
            ratingKey: "a1",
            title: "Alpha",
            thumb: nil,
            art: nil,
            year: 2001,
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
        let albumA2 = PlexAlbum(
            ratingKey: "a2",
            title: "Alpha",
            thumb: nil,
            art: nil,
            year: 2001,
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
        let service = RecordingLibraryService(
            sections: sections,
            collections: [collection],
            albumsByCollectionKey: ["c1": [albumA1, albumA2]]
        )
        let queue = RecordingCollectionsOfflineQueue(downloadedCollectionKeys: ["c1"])
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: StubSnapshotStore(snapshot: nil),
            cacheStore: InMemoryLibraryCacheStore(),
            offlineDownloadQueue: queue
        )

        await viewModel.loadCollections()

        #expect(queue.reconciliations.count == 1)
        #expect(queue.reconciliations.first?.collectionKey == "c1")
        #expect(queue.reconciliations.first?.groups.count == 1)
        #expect(queue.reconciliations.first?.groups.first?.albumRatingKeys.sorted() == ["a1", "a2"])
        #expect(queue.removedCollectionKeys.isEmpty)
    }

    @Test func refreshRemovesDownloadsForDeletedCollections() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let service = RecordingLibraryService(
            sections: [PlexLibrarySection(key: "2", title: "Music", type: "artist")],
            collections: []
        )
        let queue = RecordingCollectionsOfflineQueue(downloadedCollectionKeys: ["gone-collection"])
        let viewModel = CollectionsViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: StubSnapshotStore(snapshot: nil),
            cacheStore: InMemoryLibraryCacheStore(),
            offlineDownloadQueue: queue
        )

        await viewModel.loadCollections()

        #expect(queue.removedCollectionKeys == ["gone-collection"])
        #expect(queue.reconciliations.isEmpty)
    }
}

@MainActor
struct CollectionAlbumsViewModelTests {
    @Test func loadsAlbumsForCollectionAndDedupes() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let sections = [PlexLibrarySection(key: "2", title: "Music", type: "artist")]
        let albumA = PlexAlbum(
            ratingKey: "10",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
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
        let albumB = PlexAlbum(
            ratingKey: "11",
            title: "Album",
            thumb: nil,
            art: nil,
            year: 2022,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
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
        let service = RecordingLibraryService(
            sections: sections,
            collections: [],
            albumsByCollectionKey: ["999": [albumA, albumB]]
        )
        let viewModel = CollectionAlbumsViewModel(
            collection: PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil),
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadAlbums()

        #expect(viewModel.albums.count == 1)
        #expect(viewModel.ratingKeys(for: albumA).sorted() == ["10", "11"])
        #expect(service.lastCollectionItemsSectionId == "2")
        #expect(service.lastCollectionItemsKey == "999")
    }

    @Test func playCollectionQueuesTracksInAlbumOrder() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let collection = PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let albumA = makeAlbum(ratingKey: "a", title: "A")
        let albumB = makeAlbum(ratingKey: "b", title: "B")
        let tracksByAlbum = [
            "a": [
                PlexTrack(ratingKey: "a2", title: "A2", index: 2, parentIndex: 1, parentRatingKey: "a", duration: nil, media: nil),
                PlexTrack(ratingKey: "a1", title: "A1", index: 1, parentIndex: 1, parentRatingKey: "a", duration: nil, media: nil)
            ],
            "b": [
                PlexTrack(ratingKey: "b1", title: "B1", index: 1, parentIndex: 1, parentRatingKey: "b", duration: nil, media: nil)
            ]
        ]
        let service = RecordingLibraryService(
            sections: [PlexLibrarySection(key: "2", title: "Music", type: "artist")],
            collections: [],
            albumsByCollectionKey: [collection.ratingKey: [albumA, albumB]],
            tracksByAlbumRatingKey: tracksByAlbum
        )
        let playback = RecordingPlaybackController()
        let viewModel = CollectionAlbumsViewModel(
            collection: collection,
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            playbackController: playback,
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadAlbums()
        await viewModel.playCollection(shuffled: false)

        #expect(service.fetchedTrackAlbumKeys == ["a", "b"])
        #expect(playback.lastTracks?.map(\.ratingKey) == ["a1", "a2", "b1"])
        #expect(playback.lastStartIndex == 0)
    }

    @Test func playCollectionShuffleUsesInjectedShuffleProvider() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let collection = PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let album = makeAlbum(ratingKey: "a", title: "A")
        let tracks = [
            PlexTrack(ratingKey: "1", title: "One", index: 1, parentIndex: 1, parentRatingKey: "a", duration: nil, media: nil),
            PlexTrack(ratingKey: "2", title: "Two", index: 2, parentIndex: 1, parentRatingKey: "a", duration: nil, media: nil)
        ]
        let service = RecordingLibraryService(
            sections: [PlexLibrarySection(key: "2", title: "Music", type: "artist")],
            collections: [],
            albumsByCollectionKey: [collection.ratingKey: [album]],
            tracksByAlbumRatingKey: ["a": tracks]
        )
        let playback = RecordingPlaybackController()
        let viewModel = CollectionAlbumsViewModel(
            collection: collection,
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            playbackController: playback,
            shuffleProvider: { Array($0.reversed()) },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadAlbums()
        await viewModel.playCollection(shuffled: true)

        #expect(playback.lastTracks?.map(\.ratingKey) == ["2", "1"])
    }

    @Test func playCollectionWithNoTracksSetsError() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let collection = PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let album = makeAlbum(ratingKey: "a", title: "A")
        let service = RecordingLibraryService(
            sections: [PlexLibrarySection(key: "2", title: "Music", type: "artist")],
            collections: [],
            albumsByCollectionKey: [collection.ratingKey: [album]],
            tracksByAlbumRatingKey: ["a": []]
        )
        let playback = RecordingPlaybackController()
        let viewModel = CollectionAlbumsViewModel(
            collection: collection,
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            playbackController: playback,
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadAlbums()
        await viewModel.playCollection(shuffled: false)

        #expect(viewModel.errorMessage == "No tracks found in this collection.")
        #expect(playback.playCallCount == 0)
    }

    @Test func playCollectionUnauthorizedClearsSession() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let collection = PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let album = makeAlbum(ratingKey: "a", title: "A")
        let service = RecordingLibraryService(
            sections: [PlexLibrarySection(key: "2", title: "Music", type: "artist")],
            collections: [],
            albumsByCollectionKey: [collection.ratingKey: [album]],
            tracksByAlbumRatingKey: ["a": []],
            tracksErrorByAlbumRatingKey: ["a": PlexHTTPError.httpStatus(401, Data())]
        )
        let playback = RecordingPlaybackController()
        var invalidationCount = 0
        let viewModel = CollectionAlbumsViewModel(
            collection: collection,
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidationCount += 1 },
            playbackController: playback,
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadAlbums()
        await viewModel.playCollection(shuffled: false)

        #expect((try? tokenStore.load()) == nil)
        #expect(invalidationCount == 1)
        #expect(playback.playCallCount == 0)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
    }

    @Test func loadAlbumsSeedsMarqueeOrderOnce() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let collection = PlexCollection(ratingKey: "999", title: "Current Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        let albumsA = [makeAlbum(ratingKey: "a", title: "A"), makeAlbum(ratingKey: "b", title: "B")]
        let albumsB = [makeAlbum(ratingKey: "c", title: "C"), makeAlbum(ratingKey: "d", title: "D")]
        let service = RotatingCollectionAlbumsService(
            sectionKey: "2",
            collectionKey: collection.ratingKey,
            rounds: [albumsA, albumsB]
        )
        let viewModel = CollectionAlbumsViewModel(
            collection: collection,
            sectionKey: "2",
            tokenStore: tokenStore,
            serverStore: serverStore,
            libraryServiceFactory: { _, _ in service },
            marqueeShuffleProvider: { $0.reversed() },
            cacheStore: InMemoryLibraryCacheStore()
        )

        await viewModel.loadAlbums()
        let firstSeed = viewModel.marqueeAlbums.map(\.ratingKey)

        await viewModel.refresh()
        let secondSeed = viewModel.marqueeAlbums.map(\.ratingKey)

        #expect(firstSeed == ["b", "a"])
        #expect(secondSeed == firstSeed)
        #expect(viewModel.albums.map(\.ratingKey) == ["c", "d"])
    }

    private func makeAlbum(ratingKey: String, title: String) -> PlexAlbum {
        PlexAlbum(
            ratingKey: ratingKey,
            title: title,
            thumb: nil,
            art: nil,
            year: 2022,
            artist: "Artist",
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
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
    }
}

@MainActor
final class RecordingLibraryService: PlexLibraryServicing {
    private let sections: [PlexLibrarySection]
    private let collections: [PlexCollection]
    private let albumsByCollectionKey: [String: [PlexAlbum]]
    private let tracksByAlbumRatingKey: [String: [PlexTrack]]
    private let tracksErrorByAlbumRatingKey: [String: Error]
    private let albums: [PlexAlbum]
    private let error: Error?

    private(set) var lastCollectionsSectionId: String?
    private(set) var lastCollectionItemsSectionId: String?
    private(set) var lastCollectionItemsKey: String?
    private(set) var fetchedTrackAlbumKeys: [String] = []

    init(
        sections: [PlexLibrarySection],
        collections: [PlexCollection],
        albumsByCollectionKey: [String: [PlexAlbum]] = [:],
        tracksByAlbumRatingKey: [String: [PlexTrack]] = [:],
        tracksErrorByAlbumRatingKey: [String: Error] = [:],
        albums: [PlexAlbum] = [],
        error: Error? = nil
    ) {
        self.sections = sections
        self.collections = collections
        self.albumsByCollectionKey = albumsByCollectionKey
        self.tracksByAlbumRatingKey = tracksByAlbumRatingKey
        self.tracksErrorByAlbumRatingKey = tracksErrorByAlbumRatingKey
        self.albums = albums
        self.error = error
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        if let error { throw error }
        return sections
    }

    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        return albums
    }

    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack] {
        if let error { throw error }
        fetchedTrackAlbumKeys.append(albumRatingKey)
        if let trackError = tracksErrorByAlbumRatingKey[albumRatingKey] {
            throw trackError
        }
        return tracksByAlbumRatingKey[albumRatingKey] ?? []
    }

    func fetchAlbumDetail(albumRatingKey: String) async throws -> PlexAlbum? {
        if let error { throw error }
        return nil
    }

    func fetchCollections(sectionId: String) async throws -> [PlexCollection] {
        if let error { throw error }
        lastCollectionsSectionId = sectionId
        return collections
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        lastCollectionItemsSectionId = sectionId
        lastCollectionItemsKey = collectionKey
        return albumsByCollectionKey[collectionKey] ?? []
    }

    func fetchArtists(sectionId: String) async throws -> [PlexArtist] {
        return []
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

@MainActor
private final class RotatingCollectionAlbumsService: PlexLibraryServicing {
    private let sectionKey: String
    private let collectionKey: String
    private var rounds: [[PlexAlbum]]
    private var index = 0

    init(sectionKey: String, collectionKey: String, rounds: [[PlexAlbum]]) {
        self.sectionKey = sectionKey
        self.collectionKey = collectionKey
        self.rounds = rounds
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] { [] }
    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] { [] }
    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack] { [] }
    func fetchAlbumDetail(albumRatingKey: String) async throws -> PlexAlbum? { nil }
    func fetchCollections(sectionId: String) async throws -> [PlexCollection] { [] }
    func fetchArtists(sectionId: String) async throws -> [PlexArtist] { [] }
    func fetchArtistDetail(artistRatingKey: String) async throws -> PlexArtist? { nil }
    func fetchArtistAlbums(artistRatingKey: String) async throws -> [PlexAlbum] { [] }
    func fetchArtistTracks(artistRatingKey: String) async throws -> [PlexTrack] { [] }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        guard sectionId == sectionKey, collectionKey == self.collectionKey else { return [] }
        guard rounds.isEmpty == false else { return [] }
        let value = rounds[min(index, rounds.count - 1)]
        index += 1
        return value
    }
}

@MainActor
private final class RecordingPlaybackController: PlaybackControlling {
    private(set) var lastTracks: [PlexTrack]?
    private(set) var lastStartIndex: Int?
    private(set) var playCallCount = 0

    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
        lastTracks = tracks
        lastStartIndex = startIndex
        playCallCount += 1
    }

    func togglePlayPause() {}
    func stop() {}
    func skipToNext() {}
    func skipToPrevious() {}
    func seek(to seconds: TimeInterval) {}
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

private final class NoopArtworkPrefetcher: ArtworkPrefetching {
    func prefetch(_ requests: [ArtworkRequest]) {}
}

private final class RecordingCollectionsOfflineQueue: OfflineDownloadQueuing {
    struct Reconciliation: Equatable {
        let collectionKey: String
        let title: String
        let groups: [OfflineCollectionAlbumGroup]
    }

    private let keys: [String]
    private(set) var reconciliations: [Reconciliation] = []
    private(set) var removedCollectionKeys: [String] = []

    init(downloadedCollectionKeys: [String]) {
        self.keys = downloadedCollectionKeys
    }

    func enqueueAlbumDownload(
        albumIdentity: String,
        displayTitle: String,
        artistName: String?,
        artworkPath: String?,
        albumRatingKeys: [String],
        source: OfflineDownloadSource
    ) async throws {
    }

    func upsertCollectionRecord(
        collectionKey: String,
        title: String,
        albumIdentities: [String]
    ) async throws {
    }

    func downloadedCollectionKeys() async -> [String] {
        keys
    }

    func reconcileCollectionDownload(
        collectionKey: String,
        title: String,
        albumGroups: [OfflineCollectionAlbumGroup]
    ) async throws {
        reconciliations.append(
            Reconciliation(collectionKey: collectionKey, title: title, groups: albumGroups)
        )
    }

    func removeCollectionDownload(collectionKey: String) async throws {
        removedCollectionKeys.append(collectionKey)
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

private final class BlockingCollectionsService: PlexLibraryServicing {
    private let sections: [PlexLibrarySection]
    private let collections: [PlexCollection]
    private let gate: AsyncGate

    init(sections: [PlexLibrarySection], collections: [PlexCollection], gate: AsyncGate) {
        self.sections = sections
        self.collections = collections
        self.gate = gate
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        await gate.markStarted()
        await gate.wait()
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
        return collections
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        return []
    }

    func fetchArtists(sectionId: String) async throws -> [PlexArtist] {
        return []
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
