import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryViewModelTests {
    @Test func loadsSectionsSelectsStoredSectionAndLoadsAlbums() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: "2")
        let service = StubLibraryService(
            sections: [
                PlexLibrarySection(key: "1", title: "Video", type: "movie"),
                PlexLibrarySection(key: "2", title: "Music", type: "artist")
            ],
            albums: [
                PlexAlbum(
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
            ],
            tracks: []
        )
        var invalidated = false
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true }
        )

        await viewModel.loadSections()

        #expect(viewModel.sections.count == 1)
        #expect(viewModel.selectedSection?.key == "2")
        #expect(viewModel.albums.count == 1)
        #expect(selectionStore.key == "2")
        #expect(invalidated == false)
    }

    @Test func selectingSectionLoadsAlbums() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: nil)
        let service = StubLibraryService(
            sections: [
                PlexLibrarySection(key: "1", title: "Music", type: "artist"),
                PlexLibrarySection(key: "2", title: "More", type: "music")
            ],
            albums: [
                PlexAlbum(
                    ratingKey: "99",
                    title: "Alt",
                    thumb: nil,
                    art: nil,
                    year: 2020,
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
            ],
            tracks: []
        )
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: {}
        )

        await viewModel.selectSection(PlexLibrarySection(key: "2", title: "More", type: "music"))

        #expect(viewModel.selectedSection?.key == "2")
        #expect(viewModel.albums.first?.ratingKey == "99")
        #expect(selectionStore.key == "2")
    }

    @Test func unauthorizedClearsTokenAndInvalidatesSession() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: nil)
        let service = StubLibraryService(
            sections: [],
            albums: [],
            tracks: [],
            error: PlexHTTPError.httpStatus(401, Data())
        )
        var invalidated = false
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: { invalidated = true }
        )

        await viewModel.loadSections()

        #expect(tokenStore.token == nil)
        #expect(invalidated == true)
        #expect(viewModel.errorMessage == "Session expired. Please sign in again.")
    }

    @Test func dedupesAlbumsWhenGuidMissing() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: "1")
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
        let service = StubLibraryService(
            sections: [PlexLibrarySection(key: "1", title: "Music", type: "music")],
            albums: [albumA, albumB],
            tracks: []
        )
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            sessionInvalidationHandler: {}
        )

        await viewModel.loadSections()

        #expect(viewModel.albums.count == 1)
        #expect(viewModel.albums.first?.ratingKey == "10" || viewModel.albums.first?.ratingKey == "11")
    }

    @Test func dedupDebugLoggingRespectsSettingsToggle() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: "1")
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
        let service = StubLibraryService(
            sections: [PlexLibrarySection(key: "1", title: "Music", type: "music")],
            albums: [albumA, albumB],
            tracks: []
        )
        let settings = InMemoryAppSettingsStore()

        var logLines: [String] = []
        settings.isAlbumDedupDebugEnabled = false
        let disabledViewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            settingsStore: settings,
            logger: { logLines.append($0) },
            sessionInvalidationHandler: {}
        )
        await disabledViewModel.loadSections()
        #expect(logLines.isEmpty)

        settings.isAlbumDedupDebugEnabled = true
        let enabledViewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            settingsStore: settings,
            logger: { logLines.append($0) },
            sessionInvalidationHandler: {}
        )
        await enabledViewModel.loadSections()
        #expect(logLines.contains { $0.contains("Album De-dup Debug") })
    }

    @Test func loadsSnapshotBeforeRefreshingLive() async {
        let tokenStore = InMemoryTokenStore(token: "token")
        let serverStore = InMemoryServerStore(url: URL(string: "https://example.com:32400")!)
        let selectionStore = InMemorySelectionStore(key: "1")
        let snapshotStore = StubSnapshotStore(
            snapshot: LibrarySnapshot(
                albums: [
                    .init(
                        ratingKey: "snap",
                        title: "Snapshot Album",
                        titleSort: "Snapshot Album",
                        thumb: "/thumb/snap",
                        art: "/art/snap",
                        year: 2024,
                        artist: "Artist"
                    )
                ],
                collections: []
            )
        )
        let gate = AsyncGate()
        let service = BlockingLibraryService(
            sections: [PlexLibrarySection(key: "1", title: "Music", type: "music")],
            albums: [
                PlexAlbum(
                    ratingKey: "live",
                    title: "Live Album",
                    thumb: nil,
                    art: nil,
                    year: 2025,
                    artist: "Artist",
                    titleSort: nil,
                    originalTitle: nil,
                    editionTitle: nil,
                    guid: "plex://album/live",
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
            ],
            gate: gate
        )
        let viewModel = LibraryViewModel(
            tokenStore: tokenStore,
            serverStore: serverStore,
            selectionStore: selectionStore,
            libraryServiceFactory: { _, _ in service },
            snapshotStore: snapshotStore,
            artworkPrefetcher: NoopArtworkPrefetcher(),
            sessionInvalidationHandler: {}
        )

        let task = Task { await viewModel.loadSections() }
        await gate.waitForStart()

        #expect(viewModel.albums.first?.ratingKey == "snap")
        #expect(viewModel.isRefreshing == true)

        await gate.release()
        await task.value

        #expect(viewModel.albums.first?.ratingKey == "live")
        #expect(viewModel.isRefreshing == false)
        #expect(snapshotStore.savedSnapshot?.albums.first?.ratingKey == "live")
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

private final class NoopArtworkPrefetcher: ArtworkPrefetching {
    func prefetch(_ requests: [ArtworkRequest]) {}
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

private final class BlockingLibraryService: PlexLibraryServicing {
    private let sections: [PlexLibrarySection]
    private let albums: [PlexAlbum]
    private let gate: AsyncGate

    init(sections: [PlexLibrarySection], albums: [PlexAlbum], gate: AsyncGate) {
        self.sections = sections
        self.albums = albums
        self.gate = gate
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        await gate.markStarted()
        await gate.wait()
        return sections
    }

    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] {
        return albums
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
