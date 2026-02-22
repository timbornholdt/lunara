import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var settings: OfflineSettings
    var downloadedAlbums: [(albumID: String, album: Album?, sizeBytes: Int64)] = []
    var syncedCollections: [(collectionID: String, collection: Collection?, albumCount: Int)] = []
    var totalUsageBytes: Int64 = 0
    var activeDownloadAlbumNames: [String: String] = [:]

    private let offlineStore: OfflineStoreProtocol
    let downloadManager: DownloadManager
    private let library: LibraryRepoProtocol
    private let signOutAction: () -> Void
    let lastFMAuthManager: LastFMAuthManager?
    let scrobbleManager: ScrobbleManager?

    init(
        offlineStore: OfflineStoreProtocol,
        downloadManager: DownloadManager,
        library: LibraryRepoProtocol,
        signOutAction: @escaping () -> Void,
        lastFMAuthManager: LastFMAuthManager? = nil,
        scrobbleManager: ScrobbleManager? = nil
    ) {
        self.offlineStore = offlineStore
        self.downloadManager = downloadManager
        self.library = library
        self.signOutAction = signOutAction
        self.lastFMAuthManager = lastFMAuthManager
        self.scrobbleManager = scrobbleManager
        self.settings = OfflineSettings.load()
    }

    func load() async {
        do {
            totalUsageBytes = try await offlineStore.totalOfflineStorageBytes()
            let albumIDs = try await offlineStore.allOfflineAlbumIDs()
            var albums: [(albumID: String, album: Album?, sizeBytes: Int64)] = []
            for albumID in albumIDs {
                let tracks = try await offlineStore.offlineTracks(forAlbum: albumID)
                let size = tracks.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
                let album = try? await library.album(id: albumID)
                albums.append((albumID: albumID, album: album, sizeBytes: size))
            }
            downloadedAlbums = albums.sorted {
                let artist0 = $0.album?.artistName ?? ""
                let artist1 = $1.album?.artistName ?? ""
                if artist0 != artist1 { return artist0.localizedCaseInsensitiveCompare(artist1) == .orderedAscending }
                let title0 = $0.album?.title ?? $0.albumID
                let title1 = $1.album?.title ?? $1.albumID
                return title0.localizedCaseInsensitiveCompare(title1) == .orderedAscending
            }
        } catch {
            // Best-effort load
        }

        // Resolve names for any albums currently in the download queue
        for albumID in downloadManager.albumStates.keys {
            if activeDownloadAlbumNames[albumID] == nil {
                let album = try? await library.album(id: albumID)
                activeDownloadAlbumNames[albumID] = album?.title ?? albumID
            }
        }

        do {
            let syncedIDs = try await offlineStore.syncedCollectionIDs()
            var collections: [(collectionID: String, collection: Collection?, albumCount: Int)] = []
            for collectionID in syncedIDs {
                let collection = try? await library.collection(id: collectionID)
                let albumCount = collection?.albumCount ?? 0
                collections.append((collectionID: collectionID, collection: collection, albumCount: albumCount))
            }
            syncedCollections = collections
        } catch {
            // Best-effort load
        }
    }

    /// Active downloads derived from DownloadManager's observable albumStates.
    var activeDownloads: [(albumID: String, name: String, state: AlbumDownloadState)] {
        downloadManager.albumStates.compactMap { (albumID, state) in
            switch state {
            case .downloading, .failed:
                let name = activeDownloadAlbumNames[albumID] ?? albumID
                return (albumID: albumID, name: name, state: state)
            case .idle, .complete:
                return nil
            }
        }.sorted { $0.name < $1.name }
    }

    func downloadState(forAlbum albumID: String) -> AlbumDownloadState {
        downloadManager.downloadState(forAlbum: albumID)
    }

    func removeAlbumDownload(albumID: String) async {
        try? await downloadManager.removeDownload(forAlbum: albumID)
        await load()
    }

    func removeAllDownloads() async {
        for entry in downloadedAlbums {
            try? await downloadManager.removeDownload(forAlbum: entry.albumID)
        }
        await load()
    }

    /// Call from view's .task — refreshes downloaded albums list while downloads are active.
    func observeDownloadProgress() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { break }

            // Resolve names for any new album IDs in the download queue
            for albumID in downloadManager.albumStates.keys {
                if activeDownloadAlbumNames[albumID] == nil {
                    let album = try? await library.album(id: albumID)
                    activeDownloadAlbumNames[albumID] = album?.title ?? albumID
                }
            }

            // Refresh the downloaded albums list to pick up newly completed downloads
            if !downloadManager.albumStates.isEmpty {
                do {
                    totalUsageBytes = try await offlineStore.totalOfflineStorageBytes()
                    let albumIDs = try await offlineStore.allOfflineAlbumIDs()
                    var albums: [(albumID: String, album: Album?, sizeBytes: Int64)] = []
                    for albumID in albumIDs {
                        let tracks = try await offlineStore.offlineTracks(forAlbum: albumID)
                        let size = tracks.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
                        let album = try? await library.album(id: albumID)
                        albums.append((albumID: albumID, album: album, sizeBytes: size))
                    }
                    downloadedAlbums = albums.sorted {
                        let artist0 = $0.album?.artistName ?? ""
                        let artist1 = $1.album?.artistName ?? ""
                        if artist0 != artist1 { return artist0.localizedCaseInsensitiveCompare(artist1) == .orderedAscending }
                        let title0 = $0.album?.title ?? $0.albumID
                        let title1 = $1.album?.title ?? $1.albumID
                        return title0.localizedCaseInsensitiveCompare(title1) == .orderedAscending
                    }
                } catch {
                    // Best-effort refresh
                }
            }
        }
    }

    func unsyncCollection(collectionID: String) async {
        await downloadManager.unsyncCollection(collectionID, library: library)
        await load()
    }

    func updateStorageLimit(_ gb: Double) {
        settings.storageLimitGB = gb
        settings.save()
        downloadManager.storageLimitBytes = settings.storageLimitBytes
    }

    func updateWifiOnly(_ value: Bool) {
        settings.wifiOnly = value
        settings.save()
        downloadManager.wifiOnly = value
    }

    func signOut() {
        signOutAction()
    }

    // MARK: - Last.fm

    var isLastFMAuthenticated: Bool {
        lastFMAuthManager?.isAuthenticated ?? false
    }

    var lastFMUsername: String? {
        lastFMAuthManager?.username
    }

    var isScrobblingEnabled: Bool {
        get { scrobbleManager?.isEnabled ?? false }
        set { scrobbleManager?.isEnabled = newValue }
    }

    func signInToLastFM() async {
        do {
            try await lastFMAuthManager?.authenticate()
        } catch {
            print("[LastFM] Sign-in failed: \(error)")
        }
    }

    func completePendingLastFMAuth() async {
        guard let authManager = lastFMAuthManager, authManager.hasPendingAuth else { return }
        do {
            try await authManager.completePendingAuthentication()
        } catch {
            print("[LastFM] Auth completion failed: \(error)")
        }
    }

    func signOutOfLastFM() {
        lastFMAuthManager?.signOut()
    }

    var formattedUsage: String {
        ByteCountFormatter.string(fromByteCount: totalUsageBytes, countStyle: .file)
    }

    var formattedLimit: String {
        ByteCountFormatter.string(fromByteCount: settings.storageLimitBytes, countStyle: .file)
    }
}
