import Foundation
import Testing
@testable import Lunara

@MainActor
struct SettingsViewModelTests {

    @Test
    func load_populatesDownloadedAlbumsAndUsage() async {
        let offlineStore = MockOfflineStore()
        offlineStore.offlineAlbumIDs = ["a1"]
        offlineStore.offlineTracksByAlbumID["a1"] = [
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: Date(), fileSizeBytes: 1000)
        ]
        offlineStore.storageBytesTotal = 1000

        let vm = makeViewModel(offlineStore: offlineStore)
        await vm.load()

        #expect(vm.downloadedAlbums.count == 1)
        #expect(vm.downloadedAlbums[0].albumID == "a1")
        #expect(vm.downloadedAlbums[0].sizeBytes == 1000)
        #expect(vm.totalUsageBytes == 1000)
    }

    @Test
    func updateStorageLimit_savesAndPropagates() {
        let dm = makeDownloadManager()
        let vm = makeViewModel(downloadManager: dm)

        vm.updateStorageLimit(20)

        #expect(vm.settings.storageLimitGB == 20)
        #expect(dm.storageLimitBytes == Int64(20 * 1024 * 1024 * 1024))
    }

    @Test
    func updateWifiOnly_savesAndPropagates() {
        let dm = makeDownloadManager()
        let vm = makeViewModel(downloadManager: dm)

        vm.updateWifiOnly(false)

        #expect(vm.settings.wifiOnly == false)
        #expect(dm.wifiOnly == false)
    }

    @Test
    func signOut_callsAction() {
        var signedOut = false
        let vm = makeViewModel(signOutAction: { signedOut = true })

        vm.signOut()

        #expect(signedOut)
    }

    @Test
    func formattedUsage_returnsHumanReadable() {
        let vm = makeViewModel()
        vm.totalUsageBytes = 1_073_741_824 // 1 GB
        let usage = vm.formattedUsage
        #expect(usage.contains("1"))
    }

    // MARK: - Downloads manager (Lunara-j0l)

    @Test
    func loadThumbnailIfNeeded_resolvesArtworkForDownloadRows() async {
        let artwork = ArtworkPipelineMock()
        artwork.thumbnailResultByOwnerID["al-1"] = URL(fileURLWithPath: "/tmp/al-1.jpg")
        let vm = makeViewModel(artworkPipeline: artwork)
        let album = makeAlbum(id: "al-1")

        vm.loadThumbnailIfNeeded(for: album)
        for _ in 0..<50 where vm.thumbnailURL(for: "al-1") == nil {
            await Task.yield()
        }

        #expect(vm.thumbnailURL(for: "al-1")?.path == "/tmp/al-1.jpg")
    }

    @Test
    func makeAlbumDetailViewModel_requiresWiredDependencies() {
        let bare = makeViewModel()
        #expect(bare.makeAlbumDetailViewModel(for: makeAlbum(id: "al-x")) == nil)

        let wired = makeViewModel(
            artworkPipeline: ArtworkPipelineMock(),
            albumActions: SettingsAlbumActionsMock()
        )
        #expect(wired.makeAlbumDetailViewModel(for: makeAlbum(id: "al-x")) != nil)
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id, title: "Album \(id)", artistName: "Artist", year: nil,
            thumbURL: "/thumb/\(id)", genre: nil, rating: nil, addedAt: nil,
            trackCount: 1, duration: 180
        )
    }

    /// Lunara-dhv: a freshly queued album resolves its full metadata on demand —
    /// no waiting for the first track to download or the 3s polling tick.
    @Test
    func resolveActiveDownloadAlbum_publishesAlbumForQueuedDownload() async {
        let library = SettingsLibraryMock()
        library.albumsByID["72008"] = makeAlbum(id: "72008")
        let vm = makeViewModel(library: library)
        #expect(vm.album(forActiveDownload: "72008") == nil)

        await vm.resolveActiveDownloadAlbum(albumID: "72008")

        #expect(vm.album(forActiveDownload: "72008")?.title == "Album 72008")
        #expect(vm.album(forActiveDownload: "72008")?.artistName == "Artist")
    }

    // MARK: - Plex diagnostics credentials (Lunara-cgh)

    @Test
    func plexCredentials_comesFromInjectedProvider() async {
        let wired = makeViewModel(plexCredentialsProvider: { "http://plex.local:32400 tok-123" })
        #expect(wired.canCopyPlexCredentials)
        #expect(await wired.plexCredentials() == "http://plex.local:32400 tok-123")

        let bare = makeViewModel()
        #expect(!bare.canCopyPlexCredentials)
        #expect(await bare.plexCredentials() == nil)
    }

    // MARK: - Playback toggles (Lunara-gqo)

    @Test
    func loudnessLevelingToggle_persistsAndPlumbsToEngine() throws {
        let defaults = try makeScratchDefaults()
        let engine = PlaybackEngineMock()
        let vm = makeViewModel(playbackEngine: engine, defaults: defaults)

        #expect(vm.isLoudnessLevelingEnabled) // default on

        vm.isLoudnessLevelingEnabled = false
        #expect(defaults.object(forKey: SettingsViewModel.loudnessLevelingKey) as? Bool == false)
        #expect(engine.levelingEnabled == false)

        vm.isLoudnessLevelingEnabled = true
        #expect(engine.levelingEnabled)
    }

    @Test
    func crossfadeToggle_persistsAndPlumbsToEngine() throws {
        let defaults = try makeScratchDefaults()
        let engine = PlaybackEngineMock()
        let vm = makeViewModel(playbackEngine: engine, defaults: defaults)

        #expect(vm.isCrossfadeEnabled) // default on

        vm.isCrossfadeEnabled = false
        #expect(defaults.object(forKey: SettingsViewModel.crossfadeKey) as? Bool == false)
        #expect(engine.crossfadeEnabled == false)
    }

    private func makeScratchDefaults() throws -> UserDefaults {
        let suiteName = "settings-vm-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Helpers

    private func makeViewModel(
        offlineStore: MockOfflineStore = MockOfflineStore(),
        downloadManager: DownloadManager? = nil,
        signOutAction: @escaping () -> Void = {},
        artworkPipeline: ArtworkPipelineProtocol? = nil,
        albumActions: AlbumDetailActionRouting? = nil,
        library: LibraryRepoProtocol? = nil,
        plexCredentialsProvider: (() async -> String?)? = nil,
        playbackEngine: PlaybackEngineProtocol? = nil,
        defaults: UserDefaults = .standard
    ) -> SettingsViewModel {
        let dm = downloadManager ?? makeDownloadManager()
        return SettingsViewModel(
            offlineStore: offlineStore,
            downloadManager: dm,
            library: library ?? SettingsLibraryMock(),
            signOutAction: signOutAction,
            artworkPipeline: artworkPipeline,
            albumActions: albumActions,
            plexCredentialsProvider: plexCredentialsProvider,
            playbackEngine: playbackEngine,
            defaults: defaults
        )
    }

    private func makeDownloadManager() -> DownloadManager {
        DownloadManager(
            offlineStore: MockOfflineStore(),
            library: SettingsLibraryMock(),
            offlineDirectory: FileManager.default.temporaryDirectory
        )
    }
}

@MainActor
private final class SettingsLibraryMock: LibraryRepoProtocol {
    var albumsByID: [String: Album] = [:]

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { albumsByID[id] }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
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
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL { URL(string: "https://example.com")! }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? { nil }
}


@MainActor
final class SettingsAlbumActionsMock: AlbumDetailActionRouting {
    func playAlbum(_ album: Album) async throws { }
    func queueAlbumNext(_ album: Album) async throws { }
    func queueAlbumLater(_ album: Album) async throws { }
    func playTrackNow(_ track: Track) async throws { }
    func playTracksNow(_ tracks: [Track]) async throws { }
    func queueTrackNext(_ track: Track) async throws { }
    func queueTrackLater(_ track: Track) async throws { }
}
