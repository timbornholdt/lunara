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

    // MARK: - Helpers

    private func makeViewModel(
        offlineStore: MockOfflineStore = MockOfflineStore(),
        downloadManager: DownloadManager? = nil,
        signOutAction: @escaping () -> Void = {}
    ) -> SettingsViewModel {
        let dm = downloadManager ?? makeDownloadManager()
        return SettingsViewModel(
            offlineStore: offlineStore,
            downloadManager: dm,
            library: SettingsLibraryMock(),
            signOutAction: signOutAction
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
    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
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
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL { URL(string: "https://example.com")! }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? { nil }
}
