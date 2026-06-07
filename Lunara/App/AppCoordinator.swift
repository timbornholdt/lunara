import Foundation
import SwiftUI
import os

/// Coordinates app-wide dependencies and state
/// This is a minimal coordinator for Phase 1 - will expand in later phases
@MainActor
@Observable
final class AppCoordinator {

    // MARK: - Shared (for App Intents)

    static var shared: AppCoordinator?

    // MARK: - Dependencies

    let authManager: AuthManager
    let plexClient: PlexAPIClient
    let libraryRepo: LibraryRepoProtocol
    let artworkPipeline: ArtworkPipelineProtocol
    let playbackEngine: PlaybackEngineProtocol
    let queueManager: QueueManagerProtocol
    let appRouter: AppRouter
    let offlineStore: OfflineStoreProtocol
    let downloadManager: DownloadManager
    private let nowPlayingBridge: NowPlayingBridge
    let lastFMAuthManager: LastFMAuthManager
    let scrobbleManager: ScrobbleManager
    let gardenClient: GardenAPIClientProtocol?
    let playbackTelemetry: PlaybackTelemetry
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "AppCoordinator")

    // MARK: - State

    private(set) var isSignedIn: Bool

    private(set) var backgroundRefreshSuccessToken = 0
    private(set) var backgroundRefreshFailureToken = 0
    private(set) var lastBackgroundRefreshDate: Date?
    private(set) var lastBackgroundRefreshErrorMessage: String?

    // MARK: - Initialization

    init(
        authManager: AuthManager,
        plexClient: PlexAPIClient,
        libraryRepo: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        playbackEngine: PlaybackEngineProtocol,
        queueManager: QueueManagerProtocol,
        appRouter: AppRouter,
        offlineStore: OfflineStoreProtocol,
        downloadManager: DownloadManager,
        nowPlayingBridge: NowPlayingBridge,
        lastFMAuthManager: LastFMAuthManager,
        scrobbleManager: ScrobbleManager,
        gardenClient: GardenAPIClientProtocol? = nil,
        playbackTelemetry: PlaybackTelemetry? = nil
    ) {
        self.authManager = authManager
        self.plexClient = plexClient
        self.libraryRepo = libraryRepo
        self.artworkPipeline = artworkPipeline
        self.playbackEngine = playbackEngine
        self.queueManager = queueManager
        self.appRouter = appRouter
        self.offlineStore = offlineStore
        self.downloadManager = downloadManager
        self.nowPlayingBridge = nowPlayingBridge
        self.lastFMAuthManager = lastFMAuthManager
        self.scrobbleManager = scrobbleManager
        self.gardenClient = gardenClient
        self.playbackTelemetry = playbackTelemetry ?? PlaybackTelemetry()
        self.isSignedIn = authManager.isSignedIn
        nowPlayingBridge.configure()
        scrobbleManager.configure()
    }

    convenience init() {
        // Initialize dependencies
        let keychain = KeychainHelper()
        let serverURL = Self.loadServerURL()
        let authManager = AuthManager(keychain: keychain)
        let plexClient = PlexAPIClient(
            baseURL: serverURL,
            authManager: authManager,
            session: URLSession.shared
        )

        let libraryStore: LibraryStoreProtocol
        do {
            libraryStore = try Self.makeLibraryStore()
        } catch {
            fatalError("Failed to initialize LibraryStore: \(error)")
        }

        let artworkPipeline: ArtworkPipelineProtocol
        do {
            artworkPipeline = try Self.makeArtworkPipeline(store: libraryStore)
        } catch {
            fatalError("Failed to initialize ArtworkPipeline: \(error)")
        }

        let libraryRepo = LibraryRepo(remote: plexClient, store: libraryStore, artworkPipeline: artworkPipeline)
        let playbackTelemetry = PlaybackTelemetry()
        let crossfadeEngine = CrossfadeEngine(audioSession: AudioSession(), telemetry: playbackTelemetry)
        let playbackEngine: PlaybackEngineProtocol = crossfadeEngine
        let trackCache = TrackCache()
        let loudnessAdapter = PlexLoudnessAdapter(library: libraryRepo)

        let offlineStore: OfflineStoreProtocol
        let offlineDirectory: URL
        do {
            offlineDirectory = try Self.offlineDirectory()
            offlineStore = OfflineStore(dbQueue: (libraryStore as! LibraryStore).dbQueue, offlineDirectory: offlineDirectory)
        } catch {
            fatalError("Failed to initialize OfflineStore: \(error)")
        }

        let playbackURLResolver = PlaybackURLResolver(offlineStore: offlineStore, library: libraryRepo)
        let queueManager = QueueManager(
            engine: playbackEngine,
            persistence: FileQueueStatePersistence(),
            trackCache: trackCache,
            loudnessProvider: loudnessAdapter,
            resolver: playbackURLResolver
        )

        let appRouter = AppRouter(library: libraryRepo, queue: queueManager)

        let downloadManager = DownloadManager(
            offlineStore: offlineStore,
            library: libraryRepo,
            offlineDirectory: offlineDirectory
        )
        let loadedSettings = OfflineSettings.load()
        downloadManager.storageLimitBytes = loadedSettings.storageLimitBytes
        downloadManager.wifiOnly = loadedSettings.wifiOnly
        // When a download completes or is removed, let the queue re-resolve any
        // pre-loaded next track that now points at a stale source.
        downloadManager.onOfflineAvailabilityChanged = { [weak queueManager] changedAlbumIDs in
            queueManager?.offlineAvailabilityDidChange(forAlbums: changedAlbumIDs)
        }

        let nowPlayingBridge = NowPlayingBridge(
            engine: playbackEngine,
            queue: queueManager,
            library: libraryRepo,
            artwork: artworkPipeline
        )

        let lastFMClient = LastFMClient()
        let lastFMAuthManager = LastFMAuthManager(client: lastFMClient, keychain: keychain)
        let scrobbleManager = ScrobbleManager(
            engine: playbackEngine,
            queue: queueManager,
            library: libraryRepo,
            client: lastFMClient,
            authManager: lastFMAuthManager
        )

        let gardenClient = Self.makeGardenClient()

        self.init(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: libraryRepo,
            artworkPipeline: artworkPipeline,
            playbackEngine: playbackEngine,
            queueManager: queueManager,
            appRouter: appRouter,
            offlineStore: offlineStore,
            downloadManager: downloadManager,
            nowPlayingBridge: nowPlayingBridge,
            lastFMAuthManager: lastFMAuthManager,
            scrobbleManager: scrobbleManager,
            gardenClient: gardenClient,
            playbackTelemetry: playbackTelemetry
        )

        // Apply persisted crossfade setting
        playbackEngine.crossfadeEnabled = UserDefaults.standard.object(forKey: "crossfadeEnabled") as? Bool ?? true
    }

    // MARK: - Actions

    func loadLibraryOnLaunch() async throws -> [Album] {
        try await syncAlbums(refreshReason: .appLaunch)
    }

    func fetchAlbums() async throws -> [Album] {
        try await syncAlbums(refreshReason: .userInitiated)
    }

    func playAlbum(_ album: Album) async throws {
        try await appRouter.playAlbum(album)
    }

    func queueAlbumNext(_ album: Album) async throws {
        try await appRouter.queueAlbumNext(album)
    }

    func queueAlbumLater(_ album: Album) async throws {
        try await appRouter.queueAlbumLater(album)
    }

    func playTrackNow(_ track: Track) async throws {
        try await appRouter.playTrackNow(track)
    }

    func playTracksNow(_ tracks: [Track]) async throws {
        try await appRouter.playTracksNow(tracks)
    }

    func queueTrackNext(_ track: Track) async throws {
        try await appRouter.queueTrackNext(track)
    }

    func queueTrackLater(_ track: Track) async throws {
        try await appRouter.queueTrackLater(track)
    }

    func playCollection(_ collection: Collection) async throws {
        try await appRouter.playCollection(collection)
    }

    func shuffleCollection(_ collection: Collection) async throws {
        try await appRouter.shuffleCollection(collection)
    }

    func playArtist(_ artist: Artist) async throws {
        try await appRouter.playArtist(artist)
    }

    func shuffleArtist(_ artist: Artist) async throws {
        try await appRouter.shuffleArtist(artist)
    }

    func playPlaylist(_ playlist: Playlist) async throws {
        try await appRouter.playPlaylist(playlist)
    }

    func shufflePlaylist(_ playlist: Playlist) async throws {
        try await appRouter.shufflePlaylist(playlist)
    }

    func playAlbums(_ albums: [Album]) async throws {
        try await appRouter.playAlbums(albums)
    }

    func shuffleAlbums(_ albums: [Album]) async throws {
        try await appRouter.shuffleAlbums(albums)
    }

    func shuffleAllAlbums() async throws {
        try await appRouter.shuffleAllAlbums()
    }

    func pausePlayback() {
        appRouter.pausePlayback()
    }

    func resumePlayback() {
        appRouter.resumePlayback()
    }

    func skipToNextTrack() {
        appRouter.skipToNextTrack()
    }

    func stopPlayback() {
        appRouter.stopPlayback()
    }

    /// Persist a freshly obtained auth token and update signed-in state
    func completeSignIn(token: String) throws {
        try authManager.setToken(token)
        isSignedIn = authManager.isSignedIn
    }

    /// Sign out and clear stored token
    func signOut() {
        do {
            try authManager.clearToken()
        } catch {
            assertionFailure("Failed to clear token during sign-out: \(error)")
        }
        isSignedIn = authManager.isSignedIn
    }

    /// Reconciles all synced collections against their current album lists.
    /// Called on app launch after library refresh.
    func syncAllCollections() async {
        do {
            let syncedIDs = try await offlineStore.syncedCollectionIDs()
            guard !syncedIDs.isEmpty else { return }

            logger.info("syncAllCollections: reconciling \(syncedIDs.count) synced collections")
            for collectionID in syncedIDs {
                do {
                    let albums = try await libraryRepo.collectionAlbums(collectionID: collectionID)
                    await downloadManager.syncCollection(collectionID, albums: albums, library: libraryRepo)
                } catch {
                    logger.warning("syncAllCollections: failed to sync collection '\(collectionID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.warning("syncAllCollections: failed to load synced collection IDs: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private Helpers

    private func syncAlbums(refreshReason: LibraryRefreshReason) async throws -> [Album] {
        let cachedAlbums = try await libraryRepo.fetchAlbums()

        if !cachedAlbums.isEmpty {
            if refreshReason == .appLaunch {
                Task { [weak self] in
                    guard let self else {
                        return
                    }
                    await self.reconcileQueueAfterCatalogUpdate(trigger: "startup-cache-load")
                }
            }

            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.performBackgroundRefresh(reason: refreshReason)
            }
            return cachedAlbums
        }

        do {
            let outcome = try await libraryRepo.refreshLibrary(reason: refreshReason)
            backgroundRefreshSuccessToken += 1
            lastBackgroundRefreshDate = outcome.refreshedAt
            lastBackgroundRefreshErrorMessage = nil
        } catch let error as LunaraError {
            backgroundRefreshFailureToken += 1
            lastBackgroundRefreshErrorMessage = error.userMessage
            throw error
        } catch {
            backgroundRefreshFailureToken += 1
            lastBackgroundRefreshErrorMessage = error.localizedDescription
            throw error
        }
        await reconcileQueueAfterCatalogUpdate(trigger: "foreground-refresh-\(String(describing: refreshReason))")
        return try await libraryRepo.fetchAlbums()
    }

    private func performBackgroundRefresh(reason: LibraryRefreshReason) async {
        do {
            let outcome = try await libraryRepo.refreshLibrary(reason: reason)
            backgroundRefreshSuccessToken += 1
            lastBackgroundRefreshDate = outcome.refreshedAt
            lastBackgroundRefreshErrorMessage = nil
            logger.info("Background refresh succeeded for reason '\(String(describing: reason), privacy: .public)' at \(outcome.refreshedAt, privacy: .public)")

            if reason == .appLaunch {
                await syncAllCollections()
            } else {
                await reconcileQueueAfterCatalogUpdate(trigger: "background-refresh-\(String(describing: reason))")
            }
        } catch let error as LunaraError {
            backgroundRefreshFailureToken += 1
            lastBackgroundRefreshErrorMessage = error.userMessage
            logger.error("Background refresh failed for reason '\(String(describing: reason), privacy: .public)' with LunaraError: \(String(describing: error), privacy: .public)")
        } catch {
            backgroundRefreshFailureToken += 1
            lastBackgroundRefreshErrorMessage = error.localizedDescription
            logger.error("Background refresh failed for reason '\(String(describing: reason), privacy: .public)' with unexpected error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reconcileQueueAfterCatalogUpdate(trigger: String) async {
        do {
            let outcome = try await appRouter.reconcileQueueAgainstLibrary()
            guard outcome.removedItemCount > 0 else {
                logger.info("Queue reconciliation found no missing tracks for trigger '\(trigger, privacy: .public)'")
                return
            }

            logger.info(
                "Queue reconciliation removed \(outcome.removedItemCount, privacy: .public) queue items for trigger '\(trigger, privacy: .public)'"
            )
        } catch {
            logger.error("Queue reconciliation failed for trigger '\(trigger, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makeGardenClient() -> GardenAPIClientProtocol? {
        guard let configPath = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: configPath) as? [String: Any],
              let urlString = config["GARDEN_API_URL"] as? String,
              let baseURL = URL(string: urlString),
              let apiKey = config["GARDEN_API_KEY"] as? String,
              !apiKey.isEmpty else {
            return nil
        }
        return GardenAPIClient(baseURL: baseURL, apiKey: apiKey)
    }

    private static func loadServerURL() -> URL {
        // Try LocalConfig.plist first
        if let configPath = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath) as? [String: Any],
           let urlString = config["PLEX_SERVER_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // Default fallback (will fail, but better than crashing)
        return URL(string: "http://localhost:32400")!
    }

    private static func makeLibraryStore() throws -> LibraryStore {
        let appDirectory = try appDirectory()
        let databaseURL = appDirectory.appendingPathComponent("library.sqlite")
        return try LibraryStore(databaseURL: databaseURL)
    }

    private static func makeArtworkPipeline(store: LibraryStoreProtocol) throws -> ArtworkPipeline {
        let appDirectory = try appDirectory()
        let artworkCacheDirectoryURL = appDirectory.appendingPathComponent("artwork-cache", isDirectory: true)
        return ArtworkPipeline(
            store: store,
            session: URLSession.shared,
            cacheDirectoryURL: artworkCacheDirectoryURL
        )
    }

    private static func offlineDirectory() throws -> URL {
        let appDir = try appDirectory()
        let offlineDir = appDir.appendingPathComponent("offline-tracks", isDirectory: true)
        try FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
        return offlineDir
    }

    private static func appDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LibraryError.operationFailed(reason: "Unable to resolve application support directory.")
        }

        let appDirectory = appSupportURL.appendingPathComponent("Lunara", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory
    }
}
