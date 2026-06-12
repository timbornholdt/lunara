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
    let playbackTelemetry: PlaybackTelemetry?
    /// Artwork + navigation deps for the Downloads manager rows (Lunara-j0l);
    /// nil in contexts that don't show it.
    private let artworkPipeline: ArtworkPipelineProtocol?
    private let albumActions: AlbumDetailActionRouting?
    private let gardenClient: GardenAPIClientProtocol?
    /// Server URL + token string for external diagnostics (Lunara-cgh); nil in
    /// contexts that shouldn't expose credentials.
    private let plexCredentialsProvider: (() async -> String?)?
    /// Engine for live playback toggles (leveling/crossfade, Lunara-gqo);
    /// nil in contexts without playback.
    private let playbackEngine: PlaybackEngineProtocol?
    private let defaults: UserDefaults

    private(set) var artworkByAlbumID: [String: URL] = [:]
    private var pendingArtworkAlbumIDs: Set<String> = []

    init(
        offlineStore: OfflineStoreProtocol,
        downloadManager: DownloadManager,
        library: LibraryRepoProtocol,
        signOutAction: @escaping () -> Void,
        lastFMAuthManager: LastFMAuthManager? = nil,
        scrobbleManager: ScrobbleManager? = nil,
        playbackTelemetry: PlaybackTelemetry? = nil,
        artworkPipeline: ArtworkPipelineProtocol? = nil,
        albumActions: AlbumDetailActionRouting? = nil,
        gardenClient: GardenAPIClientProtocol? = nil,
        plexCredentialsProvider: (() async -> String?)? = nil,
        playbackEngine: PlaybackEngineProtocol? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.offlineStore = offlineStore
        self.downloadManager = downloadManager
        self.library = library
        self.signOutAction = signOutAction
        self.lastFMAuthManager = lastFMAuthManager
        self.scrobbleManager = scrobbleManager
        self.playbackTelemetry = playbackTelemetry
        self.artworkPipeline = artworkPipeline
        self.albumActions = albumActions
        self.gardenClient = gardenClient
        self.plexCredentialsProvider = plexCredentialsProvider
        self.playbackEngine = playbackEngine
        self.defaults = defaults
        self.settings = OfflineSettings.load()
    }

    // MARK: - Playback (Lunara-gqo)

    static let loudnessLevelingKey = "loudnessLevelingEnabled"
    static let crossfadeKey = "crossfadeEnabled"

    var isLoudnessLevelingEnabled: Bool {
        get { defaults.object(forKey: Self.loudnessLevelingKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.loudnessLevelingKey)
            playbackEngine?.levelingEnabled = newValue
        }
    }

    var isCrossfadeEnabled: Bool {
        get { defaults.object(forKey: Self.crossfadeKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.crossfadeKey)
            playbackEngine?.crossfadeEnabled = newValue
        }
    }

    // MARK: - Plex diagnostics credentials (Lunara-cgh)

    var canCopyPlexCredentials: Bool {
        plexCredentialsProvider != nil
    }

    func plexCredentials() async -> String? {
        await plexCredentialsProvider?()
    }

    // MARK: - Active download metadata (Lunara-dhv)

    /// Albums resolved for in-flight downloads, so a freshly queued album shows
    /// its real title/artist/art immediately instead of a Plex ID.
    private(set) var activeDownloadAlbumsByID: [String: Album] = [:]

    func album(forActiveDownload albumID: String) -> Album? {
        activeDownloadAlbumsByID[albumID]
    }

    func resolveActiveDownloadAlbum(albumID: String) async {
        guard activeDownloadAlbumsByID[albumID] == nil else { return }
        guard let album = try? await library.album(id: albumID) else { return }
        activeDownloadAlbumsByID[albumID] = album
    }

    // MARK: - Downloads manager rows (Lunara-j0l)

    func thumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadThumbnailIfNeeded(for album: Album) {
        guard let artworkPipeline else { return }
        guard thumbnailURL(for: album.plexID) == nil else { return }
        guard pendingArtworkAlbumIDs.insert(album.plexID).inserted else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let sourceURL = try await library.authenticatedThumbnailURL(for: album.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                ) {
                    self.artworkByAlbumID[album.plexID] = resolvedURL
                }
            } catch {
                // Artwork is decorative here; leave the placeholder.
            }
            self.pendingArtworkAlbumIDs.remove(album.plexID)
        }
    }

    /// Album page for a downloads row; nil when this Settings instance wasn't
    /// wired with navigation dependencies.
    func makeAlbumDetailViewModel(for album: Album) -> AlbumDetailViewModel? {
        guard let artworkPipeline, let albumActions else { return nil }
        return AlbumDetailViewModel(
            album: album,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: albumActions,
            downloadManager: downloadManager,
            gardenClient: gardenClient,
            review: album.review,
            genres: album.genres.isEmpty ? nil : album.genres,
            styles: album.styles,
            moods: album.moods
        )
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

    // MARK: - Diagnostics

    var isDiagnosticsRecordingEnabled: Bool {
        get { playbackTelemetry?.isEnabled ?? false }
        set { playbackTelemetry?.isEnabled = newValue }
    }

    var diagnosticsLogURL: URL? {
        playbackTelemetry?.exportFileURL()
    }

    func clearDiagnosticsLog() {
        playbackTelemetry?.clear()
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
