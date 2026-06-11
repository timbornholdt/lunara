import Foundation

/// Composition root: builds the full production object graph that used to live
/// inline in `AppCoordinator.init()` (Lunara-uww.5.3). Pure construction — no
/// state, no behavior — so the coordinator file stays about routing and state.
@MainActor
struct AppDependencies {
    let authManager: AuthManager
    let plexClient: PlexAPIClient
    let libraryRepo: LibraryRepoProtocol
    let artworkPipeline: ArtworkPipelineProtocol
    let playbackEngine: PlaybackEngineProtocol
    let queueManager: QueueManager
    let appRouter: AppRouter
    let offlineStore: OfflineStoreProtocol
    let downloadManager: DownloadManager
    let nowPlayingResolver: NowPlayingResolver
    let nowPlayingBridge: NowPlayingBridge
    let lastFMAuthManager: LastFMAuthManager
    let scrobbleManager: ScrobbleManager
    let lastFMClient: LastFMClientProtocol
    let gardenClient: GardenAPIClientProtocol?
    let playbackTelemetry: PlaybackTelemetry

    static func make() -> AppDependencies {
        let keychain = KeychainHelper()
        let serverURL = loadServerURL()
        let authManager = AuthManager(keychain: keychain)
        let plexClient = PlexAPIClient(
            baseURL: serverURL,
            authManager: authManager,
            session: URLSession.shared
        )

        // Concrete type (not the protocol): OfflineStore below shares its dbQueue,
        // which the protocol deliberately doesn't expose (Lunara-uww.5.1).
        let libraryStore: LibraryStore
        do {
            libraryStore = try makeLibraryStore()
        } catch {
            fatalError("Failed to initialize LibraryStore: \(error)")
        }

        let artworkPipeline: ArtworkPipelineProtocol
        do {
            artworkPipeline = try makeArtworkPipeline(store: libraryStore)
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
            offlineStore = OfflineStore(dbQueue: libraryStore.dbQueue, offlineDirectory: offlineDirectory)
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
        // Self-heal files orphaned by interrupted downloads (Lunara-uww.3.7);
        // runs before any download can start, and no-ops if one somehow has.
        Task { [weak downloadManager] in
            await downloadManager?.removeOrphanedFiles()
        }

        let nowPlayingResolver = NowPlayingResolver(library: libraryRepo, artwork: artworkPipeline)
        let nowPlayingBridge = NowPlayingBridge(
            engine: playbackEngine,
            queue: queueManager,
            resolver: nowPlayingResolver
        )

        let lastFMClient = LastFMClient()
        let lastFMAuthManager = LastFMAuthManager(client: lastFMClient, keychain: keychain)
        let scrobbleManager = ScrobbleManager(
            engine: playbackEngine,
            queue: queueManager,
            resolver: nowPlayingResolver,
            client: lastFMClient,
            authManager: lastFMAuthManager
        )

        return AppDependencies(
            authManager: authManager,
            plexClient: plexClient,
            libraryRepo: libraryRepo,
            artworkPipeline: artworkPipeline,
            playbackEngine: playbackEngine,
            queueManager: queueManager,
            appRouter: appRouter,
            offlineStore: offlineStore,
            downloadManager: downloadManager,
            nowPlayingResolver: nowPlayingResolver,
            nowPlayingBridge: nowPlayingBridge,
            lastFMAuthManager: lastFMAuthManager,
            scrobbleManager: scrobbleManager,
            lastFMClient: lastFMClient,
            gardenClient: makeGardenClient(),
            playbackTelemetry: playbackTelemetry
        )
    }

    // MARK: - Factory helpers

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
