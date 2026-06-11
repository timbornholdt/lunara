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
    /// Shared metadata/artwork resolver for the now-playing screen, bar, and
    /// lock-screen bridge, so one track change resolves track/album/artwork once
    /// instead of three times (Lunara-uww.7.1).
    let nowPlayingResolver: NowPlayingResolver
    private let nowPlayingBridge: NowPlayingBridge
    let lastFMAuthManager: LastFMAuthManager
    let scrobbleManager: ScrobbleManager
    /// Shared Last.fm client; also injected into the view environment for
    /// read-only enrichment like artist bios (Lunara-uww.6.1).
    let lastFMClient: LastFMClientProtocol
    /// MusicBrainz enrichment (artist links + external discography, Lunara-uww.6.2/6.3).
    let musicBrainzClient: MusicBrainzClientProtocol
    /// Release radar (Lunara-nlo); nil in tests that don't exercise it.
    let radarService: RadarService?
    /// Upcoming concerts near home (Lunara-uww.6.4); nil when no API key is configured.
    let ticketmasterClient: TicketmasterClientProtocol? = {
        let key = TicketmasterClient.configuredAPIKey
        return key.isEmpty ? nil : TicketmasterClient(apiKey: key)
    }()
    let gardenClient: GardenAPIClientProtocol?
    let playbackTelemetry: PlaybackTelemetry
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "AppCoordinator")

    // MARK: - State

    private(set) var isSignedIn: Bool

    /// Refresh lifecycle lives in its own service (Lunara-uww.5.3); the
    /// coordinator exposes its observable status for the list views.
    private let libraryRefresh: LibraryRefreshService
    var refreshStatus: RefreshStatusService { libraryRefresh.status }

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
        nowPlayingResolver: NowPlayingResolver,
        nowPlayingBridge: NowPlayingBridge,
        lastFMAuthManager: LastFMAuthManager,
        scrobbleManager: ScrobbleManager,
        lastFMClient: LastFMClientProtocol = LastFMClient(),
        musicBrainzClient: MusicBrainzClientProtocol = MusicBrainzClient(),
        radarService: RadarService? = nil,
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
        self.nowPlayingResolver = nowPlayingResolver
        self.nowPlayingBridge = nowPlayingBridge
        self.lastFMAuthManager = lastFMAuthManager
        self.scrobbleManager = scrobbleManager
        self.lastFMClient = lastFMClient
        self.musicBrainzClient = musicBrainzClient
        self.radarService = radarService
        self.gardenClient = gardenClient
        self.playbackTelemetry = playbackTelemetry ?? PlaybackTelemetry()
        self.libraryRefresh = LibraryRefreshService(
            library: libraryRepo,
            appRouter: appRouter,
            offlineStore: offlineStore,
            downloadManager: downloadManager
        )
        self.isSignedIn = authManager.isSignedIn
        nowPlayingBridge.configure()
        scrobbleManager.configure()
    }

    convenience init() {
        let deps = AppDependencies.make()
        self.init(
            authManager: deps.authManager,
            plexClient: deps.plexClient,
            libraryRepo: deps.libraryRepo,
            artworkPipeline: deps.artworkPipeline,
            playbackEngine: deps.playbackEngine,
            queueManager: deps.queueManager,
            appRouter: deps.appRouter,
            offlineStore: deps.offlineStore,
            downloadManager: deps.downloadManager,
            nowPlayingResolver: deps.nowPlayingResolver,
            nowPlayingBridge: deps.nowPlayingBridge,
            lastFMAuthManager: deps.lastFMAuthManager,
            scrobbleManager: deps.scrobbleManager,
            lastFMClient: deps.lastFMClient,
            musicBrainzClient: deps.musicBrainzClient,
            radarService: deps.radarService,
            gardenClient: deps.gardenClient,
            playbackTelemetry: deps.playbackTelemetry
        )

        // Apply persisted crossfade setting
        deps.playbackEngine.crossfadeEnabled = UserDefaults.standard.object(forKey: "crossfadeEnabled") as? Bool ?? true
    }

    // MARK: - Actions

    func loadLibraryOnLaunch() async throws -> [Album] {
        await purgeLegacyArtworkCacheIfNeeded()
        return try await syncAlbums(refreshReason: .appLaunch)
    }

    /// One-shot migration for Lunara-7lt: earlier builds cached full-resolution
    /// originals as "thumbnails" (up to ~10MB each), which thrashed the artwork
    /// cache and re-downloaded constantly. Thumbnails are now fetched via Plex's
    /// photo transcoder, so wipe the cache once to evict the oversized files;
    /// they're replaced lazily by downscaled versions. Runs before the first
    /// library load so nothing races the wipe.
    private func purgeLegacyArtworkCacheIfNeeded() async {
        let migrationKey = "artworkCacheSchemaV2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }
        do {
            try await artworkPipeline.invalidateAllCache()
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            // Best-effort: leave the flag unset so it retries next launch. The
            // cache also self-heals as oversized files are evicted over time.
        }
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

    /// Server URL + auth token for the Settings diagnostics copy row
    /// (Lunara-cgh), so Tim can run external queries against his library.
    func plexDiagnosticsCredentials() async -> String? {
        guard let token = try? await authManager.validToken() else { return nil }
        return "\(plexClient.baseURL.absoluteString) \(token)"
    }

    /// Reconciles all synced collections against their current album lists.
    /// Called on app launch after library refresh.
    func syncAllCollections() async {
        await libraryRefresh.syncAllCollections()
    }

    // MARK: - Private Helpers

    private func syncAlbums(refreshReason: LibraryRefreshReason) async throws -> [Album] {
        try await libraryRefresh.syncAlbums(refreshReason: refreshReason)
    }
}
