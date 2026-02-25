# Lunara: A Complete Code Walkthrough

*2026-02-25T17:14:13Z by Showboat 0.6.1*
<!-- showboat-id: cc1aa1ef-0b64-4496-ad1c-dffea18123b8 -->

Lunara is a personal iOS music player for Plex libraries. It's built in Swift/SwiftUI with a clean two-domain architecture: a **Library Domain** (Plex API, metadata caching, artwork, offline storage) and a **Music Domain** (audio playback, queue management, lock screen integration, Last.fm scrobbling). An **AppRouter** sits between them as the sole point of cross-domain coordination.

This walkthrough traces the code from app launch through the major systems, showing how everything connects.

## 1. App Entry Point

Everything begins in `LunaraApp.swift`, the @main SwiftUI App struct. It creates the AppCoordinator (the app's central nervous system) and decides whether to show the sign-in screen or the main library UI.

```bash
sed -n '1,60p' Lunara/LunaraApp.swift
```

```output
//
//  LunaraApp.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/16/26.
//

import SwiftUI
import UIKit

@main
struct LunaraApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var coordinator: AppCoordinator

    init() {
        let coord = AppCoordinator()
        _coordinator = State(initialValue: coord)
        AppCoordinator.shared = coord
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if coordinator.isSignedIn {
                    LibraryRootTabView(coordinator: coordinator)
                } else {
                    SignInView(coordinator: coordinator)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "lunara", url.host == "lastfm-callback" else { return }
                Task {
                    try? await coordinator.lastFMAuthManager.handleCallback(url: url)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
```

Key things happening here:
- The `AppCoordinator` is created once and stored as both a `@State` property and a static `shared` singleton (the singleton is needed for App Intents — Siri/Shortcuts integration).
- If the user is authenticated, they see `LibraryRootTabView`; otherwise, `SignInView`.
- The `onOpenURL` handler catches the `lunara://lastfm-callback` deep link for Last.fm OAuth.
- A custom `SceneDelegate` sets the window background color early to prevent a white flash on launch (important for the dark UI theme).

## 2. The AppCoordinator — Wiring Everything Together

The `AppCoordinator` is where all services are constructed and wired. It's the dependency injection root. Let's look at how it initializes the two domains.

```bash
sed -n '1,5p' Lunara/App/AppCoordinator.swift && echo '...' && grep -n 'init()' Lunara/App/AppCoordinator.swift | head -1 | while read line; do n=$(echo $line | cut -d: -f1); sed -n "${n},$((n+80))p" Lunara/App/AppCoordinator.swift; done
```

```output
import Foundation
import SwiftUI
import os

/// Coordinates app-wide dependencies and state
...
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
        let playbackEngine = AVQueuePlayerEngine(audioSession: AudioSession())
        let queueManager = QueueManager(engine: playbackEngine)

        let offlineStore: OfflineStoreProtocol
        let offlineDirectory: URL
        do {
            offlineDirectory = try Self.offlineDirectory()
            offlineStore = OfflineStore(dbQueue: (libraryStore as! LibraryStore).dbQueue, offlineDirectory: offlineDirectory)
        } catch {
            fatalError("Failed to initialize OfflineStore: \(error)")
        }

        let appRouter = AppRouter(library: libraryRepo, queue: queueManager, offlineStore: offlineStore)

        let downloadManager = DownloadManager(
            offlineStore: offlineStore,
            library: libraryRepo,
            offlineDirectory: offlineDirectory
        )
        let loadedSettings = OfflineSettings.load()
        downloadManager.storageLimitBytes = loadedSettings.storageLimitBytes
        downloadManager.wifiOnly = loadedSettings.wifiOnly

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
            scrobbleManager: scrobbleManager
        )
    }
```

The init follows a clear dependency graph:

1. **Auth layer**: `KeychainHelper` → `AuthManager` → `PlexAPIClient`
2. **Storage layer**: `LibraryStore` (SQLite/GRDB) → `ArtworkPipeline` (disk-cached images)
3. **Library facade**: `LibraryRepo` (wraps remote API + local store)
4. **Music layer**: `AudioSession` → `AVQueuePlayerEngine` → `QueueManager`
5. **Router**: `AppRouter` (bridges Library ↔ Music)
6. **Offline**: `OfflineStore` + `DownloadManager`
7. **System integration**: `NowPlayingBridge` (lock screen) + `ScrobbleManager` (Last.fm)

Every dependency is injected via protocols, making the entire app testable with mocks.

## 3. Data Models

Lunara's core types live in `Lunara/Shared/Models/`. They're simple value types — structs that are `Codable`, `Equatable`, `Hashable`, and `Sendable` (safe across concurrency boundaries).

```bash
cat Lunara/Shared/Models/Album.swift
```

```output
import Foundation

/// Represents an album in the Plex library.
/// This is a pure data type shared across Library and Music domains.
struct Album: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Plex's unique identifier for this album
    let plexID: String

    /// Album title
    let title: String

    /// Primary album artist name
    let artistName: String

    /// Release year (if available)
    let year: Int?

    /// Full release date (if available from Plex's originallyAvailableAt)
    let releaseDate: Date?

    /// URL to album artwork thumbnail from Plex
    let thumbURL: String?

    /// Primary genre (if available)
    let genre: String?

    /// Album review/summary text from metadata providers.
    let review: String?

    /// All reported genres for this album.
    let genres: [String]

    /// All reported styles for this album.
    let styles: [String]

    /// All reported moods for this album.
    let moods: [String]

    /// User's star rating (0-10 scale, Plex standard)
    let rating: Int?

    /// When this album was added to the library
    let addedAt: Date?

    /// Number of tracks on this album
    let trackCount: Int

    /// Total duration of all tracks in seconds
    let duration: TimeInterval

    init(
        plexID: String,
        title: String,
        artistName: String,
        year: Int?,
        releaseDate: Date? = nil,
        thumbURL: String?,
        genre: String?,
        rating: Int?,
        addedAt: Date?,
        trackCount: Int,
        duration: TimeInterval,
        review: String? = nil,
        genres: [String] = [],
        styles: [String] = [],
        moods: [String] = []
    ) {
        self.plexID = plexID
        self.title = title
        self.artistName = artistName
        self.year = year
        self.releaseDate = releaseDate
        self.thumbURL = thumbURL
        self.genre = genre
        self.rating = rating
        self.addedAt = addedAt
        self.trackCount = trackCount
        self.duration = duration
        self.review = review
        self.genres = genres
        self.styles = styles
        self.moods = moods
    }

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Human-readable duration string (e.g., "42:30")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Album display subtitle combining artist and release date/year
    var subtitle: String {
        if let releaseDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "\(artistName) • \(formatter.string(from: releaseDate))"
        }
        if let year = year {
            return "\(artistName) • \(year)"
        }
        return artistName
    }

    /// Whether this album has been rated
    var isRated: Bool {
        rating != nil && rating! > 0
    }
}
```

```bash
cat Lunara/Shared/Models/Track.swift
```

```output
import Foundation

/// Represents a track in the Plex library.
/// This is a pure data type shared across Library and Music domains.
struct Track: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Plex's unique identifier for this track
    let plexID: String

    /// ID of the album this track belongs to
    let albumID: String

    /// Track title
    let title: String

    /// Track number within the album
    let trackNumber: Int

    /// Track duration in seconds
    let duration: TimeInterval

    /// Track artist name (may differ from album artist for compilations)
    let artistName: String

    /// Plex media key used for URL construction
    let key: String

    /// URL to track-specific artwork (optional, usually inherits from album)
    let thumbURL: String?

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Human-readable duration string (e.g., "3:42")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Track display with number (e.g., "1. Song Title")
    var displayTitle: String {
        "\(trackNumber). \(title)"
    }
}
```

The `Album` model is rich — it carries genres, styles, moods, reviews, and ratings from Plex metadata providers. The `Track` model is leaner, carrying just what's needed for display and playback URL construction (the `key` field is the Plex media key used to build streaming URLs).

There are also `Artist` and `Collection` models following the same pattern, plus a `PlaybackState` enum that drives all UI reactivity.

```bash
cat Lunara/Shared/Models/PlaybackState.swift
```

```output
import Foundation

/// Represents the current state of the playback engine.
/// This is a shared type used by both Music domain and UI layer.
enum PlaybackState: Equatable, Sendable {
    /// No track is loaded or ready to play
    case idle

    /// A track is loading (streaming URL buffering, AVPlayerItem preparing)
    /// UI should show loading indicators to distinguish from paused state
    case buffering

    /// A track is actively playing
    case playing

    /// Playback is paused (track is loaded and ready to resume)
    case paused

    /// Playback encountered an error
    /// Associated string contains a user-facing error message
    case error(String)

    // MARK: - Computed Properties

    /// Whether audio is currently playing
    var isPlaying: Bool {
        self == .playing
    }

    /// Whether the player is in a loading state
    var isBuffering: Bool {
        self == .buffering
    }

    /// Whether playback can be resumed
    var canResume: Bool {
        self == .paused
    }

    /// Whether the player is in an error state
    var hasError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    /// Error message if in error state, nil otherwise
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}
```

The `.buffering` state is critical — it lets the UI show a spinner instead of a play button while a stream loads. Without it, users would see a confusing pause state when they just tapped play. The 5-state machine (`idle → buffering → playing ⇄ paused`, with `error` as a terminal branch) drives every piece of playback UI in the app.

## 4. The Library Domain

The Library domain handles all communication with the Plex server and caches everything locally in SQLite. It's organized as three layers: **PlexAPIClient** (HTTP), **LibraryStore** (SQLite/GRDB), and **LibraryRepo** (the public facade).

### 4a. PlexAPIClient — The HTTP Layer

The API client handles all Plex server communication. Plex uses XML responses in a "MediaContainer" format, so the client includes custom XML parsing. Let's look at how it fetches albums.

```bash
sed -n '37,92p' Lunara/Library/API/PlexAPIClient.swift
```

```output
    func fetchAlbums() async throws -> [Album] {
        let endpoint = "/library/sections/4/all"
        let request = try await buildRequest(
            path: endpoint,
            queryItems: [URLQueryItem(name: "type", value: "9")],
            requiresAuth: true
        )

        let (data, _) = try await executeLoggedRequest(request, operation: "fetchAlbums")

        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let directories = container.directories else {
            return []
        }

        var albums: [Album] = []
        albums.reserveCapacity(directories.count)

        for directory in directories {
            guard directory.type == "album" else { continue }
            guard let albumID = directory.ratingKey, !albumID.isEmpty else {
                logger.error(
                    "Album directory missing required ratingKey. title='\(directory.title, privacy: .public)' key='\(directory.key, privacy: .public)'"
                )
                throw LibraryError.invalidResponse
            }

            let addedAtDate = directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let durationSeconds = directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0.0
            let resolvedGenres = dedupedTags(directory.genres + [directory.genre].compactMap { $0 })
            let releaseDate = directory.originallyAvailableAt.flatMap { Self.parseReleaseDateString($0) }

            albums.append(Album(
                plexID: albumID,
                title: directory.title,
                artistName: directory.parentTitle ?? "Unknown Artist",
                year: directory.year,
                releaseDate: releaseDate,
                thumbURL: directory.thumb,
                genre: resolvedGenres.first,
                rating: directory.rating.map { Int($0) },
                addedAt: addedAtDate,
                trackCount: directory.leafCount ?? 0,
                duration: durationSeconds,
                review: directory.summary,
                genres: resolvedGenres,
                styles: dedupedTags(directory.styles),
                moods: dedupedTags(directory.moods)
            ))
        }

        return albums
    }

    /// Fetch tracks for a specific album
    /// - Parameter albumID: Plex rating key for the album
```

```bash
sed -n '134,170p' Lunara/Library/API/PlexAPIClient.swift
```

```output
    func streamURL(forTrack track: Track) async throws -> URL {
        let token = try await authManager.validToken()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = track.key
        components.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components.url else {
            throw LibraryError.invalidResponse
        }

        return url
    }

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let token = try await authManager.validToken()

        let initialURL: URL?
        if let parsed = URL(string: rawValue), parsed.scheme != nil {
            initialURL = parsed
        } else if rawValue.hasPrefix("/") {
            initialURL = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
        } else {
            initialURL = URL(string: "/\(rawValue)", relativeTo: baseURL)?.absoluteURL
        }

        guard let resolvedURL = initialURL else {
            return nil
        }

        guard var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false) else {
            return nil
```

The API client uses Plex's convention: section 4 is music, type 9 is albums. The XML response is decoded into a `PlexMediaContainer` struct, then each "Directory" entry is mapped to an `Album`. Notice the defensive coding — missing `ratingKey` throws an error rather than silently skipping.

The `streamURL` method is simple: it constructs a URL from the track's `key` field and appends the auth token as a query parameter. This URL is what AVQueuePlayer will stream from.

### 4b. LibraryStore — SQLite Persistence

The store uses GRDB (a Swift SQLite ORM) to cache all metadata locally. This means the app launches instantly from cache without waiting for the network.

```bash
sed -n '25,100p' Lunara/Library/Store/LibraryStore.swift
```

```output
    func fetchAlbums(page: LibraryPage) async throws -> [Album] {
        let pageSize = page.size
        let pageOffset = page.offset

        return try await dbQueue.read { db in
            let records = try AlbumRecord
                .order(Column("artistName").asc, Column("title").asc)
                .limit(pageSize, offset: pageOffset)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func fetchAlbum(id: String) async throws -> Album? {
        try await dbQueue.read { db in
            try AlbumRecord.fetchOne(db, key: id)?.model
        }
    }

    func upsertAlbum(_ album: Album) async throws {
        let target = album
        try await dbQueue.write { db in
            try AlbumRecord(model: target).save(db)
        }
    }

    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        let targetAlbumID = albumID

        return try await dbQueue.read { db in
            let records = try TrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .order(Column("trackNumber").asc, Column("title").asc)
                .fetchAll(db)
            return records.map(\.model)
        }
    }

    func track(id: String) async throws -> Track? {
        try await dbQueue.read { db in
            try TrackRecord.fetchOne(db, key: id)?.model
        }
    }

    func replaceTracks(_ tracks: [Track], forAlbum albumID: String) async throws {
        let targetAlbumID = albumID
        let replacementTracks = tracks
        try await dbQueue.write { db in
            _ = try TrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .deleteAll(db)

            for track in replacementTracks {
                try TrackRecord(model: track).save(db)
            }
        }
    }

    func fetchArtists() async throws -> [Artist] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.*,
                       COALESCE(ac.cnt, 0) AS computedAlbumCount
                FROM artists a
                LEFT JOIN (
                    SELECT artistName, COUNT(*) AS cnt
                    FROM albums
                    GROUP BY artistName
                ) ac ON ac.artistName = a.name
                ORDER BY COALESCE(a.sortName, a.name) ASC, a.name ASC
                """)
            return try rows.map { row in
                let record = try ArtistRecord(row: row)
                let base = record.model
                let count: Int = row["computedAlbumCount"]
                return Artist(
```

GRDB's `dbQueue.read` and `dbQueue.write` blocks provide async-safe database access. The store uses an intermediary `AlbumRecord`/`TrackRecord` layer (GRDB's `PersistableRecord` protocol) that maps to and from the domain `Album`/`Track` structs. Notice how `replaceTracks` is atomic — it deletes all existing tracks for an album and inserts the new ones in a single write transaction.

The artist query is interesting: it does a LEFT JOIN to compute album counts from the albums table rather than trusting Plex's reported count, ensuring accuracy after deduplication.

### 4c. LibraryRepo — The Public Facade

LibraryRepo is the only Library-domain type that Views and the AppRouter see. It implements a **cache-on-refresh** strategy: serve cached data immediately, refresh from the network in the background.

```bash
sed -n '62,120p' Lunara/Library/Repo/LibraryRepo.swift
```

```output
    func albums(page: LibraryPage) async throws -> [Album] {
        try await store.fetchAlbums(page: page)
    }

    func album(id: String) async throws -> Album? {
        let cachedAlbum = try await store.fetchAlbum(id: id)
        if let cachedAlbum {
            return cachedAlbum
        }

        guard let remoteAlbum = try await remote.fetchAlbum(id: id) else {
            return nil
        }

        try await store.upsertAlbum(remoteAlbum)
        return remoteAlbum
    }

    func searchAlbums(query: String) async throws -> [Album] {
        try await store.searchAlbums(query: query)
    }

    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        try await store.queryAlbums(filter: filter)
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        let cachedTracks = try await store.fetchTracks(forAlbum: albumID)
        if !cachedTracks.isEmpty {
            return cachedTracks
        }

        let remoteTracks = try await remote.fetchTracks(forAlbum: albumID)
        try await store.replaceTracks(remoteTracks, forAlbum: albumID)
        return remoteTracks
    }

    func track(id: String) async throws -> Track? {
        if let cachedTrack = try await store.track(id: id) {
            return cachedTrack
        }

        guard let remoteTrack = try await remote.fetchTrack(id: id) else {
            return nil
        }

        try await store.replaceTracks([remoteTrack], forAlbum: remoteTrack.albumID)
        return remoteTrack
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        async let remoteAlbumTask = remote.fetchAlbum(id: albumID)
        async let remoteTracksTask = remote.fetchTracks(forAlbum: albumID)

        let remoteAlbum = try await remoteAlbumTask
        let remoteTracks = try await remoteTracksTask

        if let remoteAlbum {
            try await store.upsertAlbum(remoteAlbum)
```

```bash
sed -n '258,310p' Lunara/App/AppCoordinator.swift
```

```output
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

        _ = try await libraryRepo.refreshLibrary(reason: refreshReason)
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
```

This is the cache-on-refresh pattern in action:

1. **Cache hit** (common path): Return cached albums immediately. Fire off a background refresh that won't block the UI. Also reconcile the queue in case cached tracks have gone stale.
2. **Cache miss** (first launch): Wait for the network fetch, then return the results.

After a background refresh completes, the coordinator reconciles the playback queue — if Plex removed tracks from the library, those tracks need to be removed from the queue too. This is a subtle but important detail for a music player.

## 5. The Music Domain

The Music domain is completely independent of Plex. It only knows about URLs and track IDs — it has no idea where the audio comes from. This separation is what makes the architecture clean.

### 5a. PlaybackEngine — AVQueuePlayer Wrapper

```bash
cat Lunara/Music/Engine/PlaybackEngineProtocol.swift
```

```output
import Foundation
import Observation

@MainActor
protocol PlaybackEngineProtocol: AnyObject, Observable {
    var playbackState: PlaybackState { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var currentTrackID: String? { get }

    func play(url: URL, trackID: String)
    func pause()
    func resume()
    func seek(to time: TimeInterval)
    func stop()
}

```

```bash
sed -n '88,160p' Lunara/Music/Engine/AVQueuePlayerEngine.swift
```

```output
        wireDependencies()
    }

    func play(url: URL, trackID: String) {
        do {
            try audioSession.configureForPlayback()
        } catch {
            transitionToError(MusicError.audioSessionFailed.userMessage)
            return
        }

        currentTrackID = trackID
        activePlaybackURL = url
        hasLoggedFailureForActivePlayback = false
        elapsed = 0
        duration = 0

        transitionToBuffering()
        driver.play(url: url, trackID: trackID)
    }

    func pause() {
        cancelBufferingTimeout()
        driver.pause()
        if playbackState != .idle && !playbackState.hasError {
            playbackState = .paused
        }
    }

    func resume() {
        guard currentTrackID != nil else {
            transitionToError(MusicError.invalidState(reason: "No track is loaded.").userMessage)
            return
        }

        transitionToBuffering()
        driver.resume()
    }

    func seek(to time: TimeInterval) {
        driver.seek(to: time)
        elapsed = max(0, time)
    }

    func stop() {
        cancelBufferingTimeout()
        driver.stop()
        playbackState = .idle
        currentTrackID = nil
        elapsed = 0
        duration = 0
    }

    private func wireDependencies() {
        driver.onTimeControlStatusChanged = { [weak self] status in
            self?.handleTimeControlStatus(status)
        }

        driver.onCurrentTrackIDChanged = { [weak self] trackID in
            self?.currentTrackID = trackID
        }

        driver.onCurrentItemFailed = { [weak self] message in
            self?.logPlaybackFailureIfNeeded(reason: message)
            self?.transitionToError(message)
        }

        driver.onCurrentItemEnded = { [weak self] in
            guard let self else { return }
            self.currentTrackID = nil
            self.playbackState = .idle
            self.elapsed = 0
            self.duration = 0
```

```bash
sed -n '170,220p' Lunara/Music/Engine/AVQueuePlayerEngine.swift
```

```output
            self.duration = duration
        }

        audioSession.onInterruptionBegan = { [weak self] in
            self?.pause()
        }

        audioSession.onInterruptionEnded = { [weak self] shouldResume in
            guard shouldResume else { return }
            self?.resume()
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            if playbackState != .idle && !playbackState.hasError {
                transitionToBuffering()
            }
        case .playing:
            cancelBufferingTimeout()
            if playbackState != .playing {
                playbackState = .playing
            }
        case .paused:
            if playbackState == .idle || playbackState.hasError || playbackState == .buffering {
                return
            }
            playbackState = .paused
        @unknown default:
            break
        }
    }

    private func transitionToBuffering() {
        playbackState = .buffering
        scheduleBufferingTimeout()
    }

    private func transitionToError(_ message: String) {
        cancelBufferingTimeout()
        playbackState = .error(message)
        driver.stop()
    }

    private func scheduleBufferingTimeout() {
        cancelBufferingTimeout()
        bufferingTimeoutTask = timeoutScheduler.schedule(after: bufferingTimeout) { [weak self] in
            guard let self else { return }
            if self.playbackState == .buffering {
                self.transitionToError(
```

The engine is a thin stateful wrapper around AVQueuePlayer. Key design decisions:

- **Audio session first**: Before playing anything, it configures the AVAudioSession for `.playback` mode (required for background audio).
- **Buffering timeout**: If the stream hasn't started playing within 8 seconds, it transitions to an error state rather than hanging forever.
- **Interruption handling**: Phone calls and Siri pause playback automatically; when the interruption ends, the system tells us whether to resume.
- **Track end detection**: When `onCurrentItemEnded` fires, the engine resets to `.idle` — this is the signal that QueueManager watches to auto-advance.
- **Driver pattern**: The actual AVQueuePlayer calls are delegated to `AVQueuePlayerDriver`, keeping the state machine logic separate from Apple's API surface.

### 5b. QueueManager — Playlist and Auto-Advance

The QueueManager maintains the ordered playlist and automatically advances to the next track when one finishes.

```bash
sed -n '38,130p' Lunara/Music/Queue/QueueManager.swift
```

```output
    func playNow(_ items: [QueueItem]) {
        guard !items.isEmpty else {
            clear()
            return
        }

        self.items = items
        currentIndex = 0
        pendingSeekAfterNextPlay = nil

        playCurrentItem()
    }

    func playNext(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }

        if currentIndex == nil || self.items.isEmpty {
            self.items = items
            currentIndex = 0
            pendingSeekAfterNextPlay = nil
            playCurrentItem()
            return
        }

        let insertionIndex = min((currentIndex ?? 0) + 1, self.items.count)
        self.items.insert(contentsOf: items, at: insertionIndex)
        persistQueueState(elapsed: engine.elapsed)
    }

    func playLater(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }
        self.items.append(contentsOf: items)

        if currentIndex == nil {
            currentIndex = 0
        }

        persistQueueState(elapsed: engine.elapsed)
    }

    func play() {
        if engine.currentTrackID == nil {
            playCurrentItem()
        } else {
            engine.resume()
        }
    }

    func pause() {
        engine.pause()
        persistQueueState(elapsed: engine.elapsed)
    }

    func resume() {
        if engine.currentTrackID == nil {
            playCurrentItem()
        } else {
            engine.resume()
        }
    }

    func skipToNext() {
        advanceAndPlayNextIfPossible()
    }

    func skipBack() {
        guard let currentIndex else { return }
        if engine.elapsed > 3 {
            engine.seek(to: 0)
            persistQueueState(elapsed: 0)
        } else {
            let prevIndex = currentIndex - 1
            guard items.indices.contains(prevIndex) else {
                engine.seek(to: 0)
                persistQueueState(elapsed: 0)
                return
            }
            self.currentIndex = prevIndex
            pendingSeekAfterNextPlay = nil
            playCurrentItem()
        }
    }

    func clear() {
        items = []
        currentIndex = nil
        pendingSeekAfterNextPlay = nil
        lastPersistedElapsed = 0
        engine.stop()
        enqueuePersistenceTask(
            operation: { [persistence] in
                try await persistence.clear()
            },
```

```bash
sed -n '230,280p' Lunara/Music/Queue/QueueManager.swift
```

```output
            }
        }
    }

    private func observeEngineState() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.engine.currentTrackID
            _ = self.engine.playbackState
            _ = self.engine.elapsed
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleEngineStateChange()
                self?.observeEngineState()
            }
        }
    }

    private func handleEngineStateChange() {
        if engine.currentTrackID == nil, engine.playbackState == .idle {
            advanceAndPlayNextIfPossible()
        }

        if shouldPersistElapsedProgress() {
            persistQueueState(elapsed: engine.elapsed)
        }
    }

    private func shouldPersistElapsedProgress() -> Bool {
        guard engine.currentTrackID != nil else { return false }
        guard engine.playbackState == .playing else { return false }

        let elapsed = max(0, engine.elapsed)
        if elapsed < lastPersistedElapsed {
            return true
        }

        return (elapsed - lastPersistedElapsed) >= 5
    }

    func applyReconciledItems(_ items: [QueueItem]) {
        self.items = items
    }

    func applyReconciledCurrentIndex(_ index: Int?) {
        currentIndex = index
    }
}
```

The queue's auto-advance is elegantly simple: it uses Swift's `withObservationTracking` to watch the engine's `currentTrackID` and `playbackState`. When a track ends, the engine sets `currentTrackID = nil` and `playbackState = .idle` — the queue sees this and calls `advanceAndPlayNextIfPossible()`.

The `skipBack` method has a nice UX touch: if you're more than 3 seconds into a track, it restarts the current track; if you're in the first 3 seconds, it goes to the previous track. This matches how every good music player works.

Queue state is persisted to disk every 5 seconds of playback progress, so if the app is killed, it can restore where you were.

## 6. The AppRouter — Cross-Domain Bridge

The AppRouter is the **only place** where Library and Music domains interact. It translates user intent ("play this album") into cross-domain operations (fetch tracks from Library, resolve URLs, send to Music queue).

```bash
sed -n '24,80p' Lunara/Router/AppRouter.swift
```

```output
    func resolveURL(for track: Track) async throws -> URL {
        if let offlineStore, let localURL = try await offlineStore.localFileURL(forTrackID: track.plexID) {
            return localURL
        }
        return try await library.streamURL(for: track)
    }

    func playAlbum(_ album: Album) async throws {
        logger.info("playAlbum started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = try await queueItems(for: tracks, actionName: "playAlbum")

        logEnqueueReport(album: album, tracks: tracks, items: items)
        queue.playNow(items)
        logger.info("playAlbum queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func queueAlbumNext(_ album: Album) async throws {
        logger.info("queueAlbumNext started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = try await queueItems(for: tracks, actionName: "queueAlbumNext")
        queue.playNext(items)
        logger.info("queueAlbumNext queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func queueAlbumLater(_ album: Album) async throws {
        logger.info("queueAlbumLater started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = try await queueItems(for: tracks, actionName: "queueAlbumLater")
        queue.playLater(items)
        logger.info("queueAlbumLater queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func playTrackNow(_ track: Track) async throws {
        let item = try await queueItem(for: track, actionName: "playTrackNow")
        queue.playNow([item])
    }

    func queueTrackNext(_ track: Track) async throws {
        let item = try await queueItem(for: track, actionName: "queueTrackNext")
        queue.playNext([item])
    }

    func queueTrackLater(_ track: Track) async throws {
        let item = try await queueItem(for: track, actionName: "queueTrackLater")
        queue.playLater([item])
    }

    func playCollection(_ collection: Collection) async throws {
        logger.info("playCollection started for collection '\(collection.title, privacy: .public)' id '\(collection.plexID, privacy: .public)'")
        let items = try await allQueueItemsForCollection(collection)
        queue.playNow(items)
        logger.info("playCollection queued \(items.count, privacy: .public) items for collection id '\(collection.plexID, privacy: .public)'")
    }

    func shuffleCollection(_ collection: Collection) async throws {
        logger.info("shuffleCollection started for collection '\(collection.title, privacy: .public)' id '\(collection.plexID, privacy: .public)'")
```

```bash
sed -n '127,200p' Lunara/Router/AppRouter.swift
```

```output
    func reconcileQueueAgainstLibrary() async throws -> QueueReconciliationOutcome {
        let queuedItems = queue.items
        guard !queuedItems.isEmpty else {
            return .noChanges
        }

        var missingTrackIDs: Set<String> = []
        var trackLookupCache: [String: Bool] = [:]
        trackLookupCache.reserveCapacity(queuedItems.count)

        for item in queuedItems {
            if let isPresent = trackLookupCache[item.trackID] {
                if !isPresent {
                    missingTrackIDs.insert(item.trackID)
                }
                continue
            }

            let track = try await library.track(id: item.trackID)
            let isPresent = track != nil
            trackLookupCache[item.trackID] = isPresent
            if !isPresent {
                missingTrackIDs.insert(item.trackID)
            }
        }

        guard !missingTrackIDs.isEmpty else {
            return .noChanges
        }

        let removedItemCount = queuedItems.filter { missingTrackIDs.contains($0.trackID) }.count
        queue.reconcile(removingTrackIDs: missingTrackIDs)
        let sortedMissingTrackIDs = missingTrackIDs.sorted()
        logger.info(
            "Queue reconciliation removed \(removedItemCount, privacy: .public) items for missing track IDs: \(sortedMissingTrackIDs.joined(separator: ","), privacy: .public)"
        )
        return QueueReconciliationOutcome(
            removedTrackIDs: sortedMissingTrackIDs,
            removedItemCount: removedItemCount
        )
    }

    private func allQueueItemsForCollection(_ collection: Collection) async throws -> [QueueItem] {
        let albums = try await library.collectionAlbums(collectionID: collection.plexID)
        guard !albums.isEmpty else {
            logger.error("Found zero albums for collection id '\(collection.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "albums", id: collection.plexID)
        }

        let allItems = try await allQueueItemsForAlbums(albums, actionName: "collection-\(collection.plexID)")

        guard !allItems.isEmpty else {
            logger.error("Found zero tracks across \(albums.count, privacy: .public) albums for collection id '\(collection.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: collection.plexID)
        }

        return allItems
    }

    private func allQueueItemsForArtist(_ artist: Artist) async throws -> [QueueItem] {
        let albums = try await library.artistAlbums(artistName: artist.name)
        guard !albums.isEmpty else {
            logger.error("Found zero albums for artist id '\(artist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "albums", id: artist.plexID)
        }

        let allItems = try await allQueueItemsForAlbums(albums, actionName: "artist-\(artist.plexID)")

        guard !allItems.isEmpty else {
            logger.error("Found zero tracks across \(albums.count, privacy: .public) albums for artist id '\(artist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: artist.plexID)
        }

        return allItems
```

The router's `resolveURL` method is the key bridge: it checks the offline store first (local file on disk), falling back to a Plex streaming URL. Every playback action follows the same pattern:

1. Fetch tracks from the Library domain
2. Resolve each track to a URL (offline or streaming)
3. Create `QueueItem`s (trackID + URL pairs)
4. Hand them to the QueueManager

The reconciliation method runs after every library refresh. It checks each queued track against the library — if Plex removed a track (re-tagged album, deleted file), it's removed from the queue. The lookup cache prevents redundant database hits when the same track appears multiple times.

## 7. The View Layer

Views follow a consistent pattern: a SwiftUI View paired with an `@Observable` ViewModel that communicates with the coordinator through an `ActionRouting` protocol.

### 7a. LibraryGridView — The Album Browser

```bash
sed -n '1,100p' Lunara/Views/Library/LibraryGridView.swift
```

```output
import SwiftUI
import UIKit

struct LibraryGridView: View {
    @Environment(\.showNowPlaying) private var showNowPlaying
    @State private var viewModel: LibraryGridViewModel
    @State private var selectedAlbum: Album?
    @Binding var externalSelectedAlbum: Album?
    private let backgroundRefreshSuccessToken: Int
    private let backgroundRefreshFailureToken: Int
    private let backgroundRefreshErrorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)
    ]

    init(
        viewModel: LibraryGridViewModel,
        backgroundRefreshSuccessToken: Int = 0,
        backgroundRefreshFailureToken: Int = 0,
        backgroundRefreshErrorMessage: String? = nil,
        externalSelectedAlbum: Binding<Album?> = .constant(nil)
    ) {
        _viewModel = State(initialValue: viewModel)
        self.backgroundRefreshSuccessToken = backgroundRefreshSuccessToken
        self.backgroundRefreshFailureToken = backgroundRefreshFailureToken
        self.backgroundRefreshErrorMessage = backgroundRefreshErrorMessage
        _externalSelectedAlbum = externalSelectedAlbum
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Albums")
                            .lunaraHeading(.section, weight: .semibold)
                            .lineLimit(1)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await viewModel.shuffleAll()
                                showNowPlaying.wrappedValue = true
                            }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .disabled(viewModel.albums.isEmpty)
                    }
                }
                .toolbarBackground(Color.lunara(.backgroundBase), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search albums or artists"))
                .navigationDestination(item: $selectedAlbum) { album in
                    AlbumDetailView(viewModel: viewModel.makeAlbumDetailViewModel(for: album))
                }
                .lunaraLinenBackground()
                .lunaraErrorBanner(using: viewModel.errorBannerState)
                .task {
                    await viewModel.loadInitialIfNeeded()
                }
                .task(id: backgroundRefreshSuccessToken) {
                    await viewModel.applyBackgroundRefreshUpdateIfNeeded(successToken: backgroundRefreshSuccessToken)
                }
                .task(id: backgroundRefreshFailureToken) {
                    viewModel.applyBackgroundRefreshFailureIfNeeded(
                        failureToken: backgroundRefreshFailureToken,
                        message: backgroundRefreshErrorMessage
                    )
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .onChange(of: externalSelectedAlbum) { _, newAlbum in
                    if let newAlbum {
                        selectedAlbum = newAlbum
                        externalSelectedAlbum = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.albums.isEmpty,
           case .loading = viewModel.loadingState {
            VStack {
                Spacer()
                ProgressView("Loading albums...")
                Spacer()
            }
        } else if viewModel.albums.isEmpty,
                  case .error(let message) = viewModel.loadingState {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
```

The view structure follows SwiftUI best practices:

- **`NavigationStack`** at the root with `.navigationDestination` for drill-down to album detail.
- **`.task`** modifier triggers initial data loading (non-blocking, async).
- **`.task(id:)`** watches background refresh tokens — when the coordinator finishes a background refresh, the token increments and the view reloads.
- **`.refreshable`** enables pull-to-refresh.
- **`.searchable`** provides the search bar.
- **`.lunaraErrorBanner`** is a custom modifier that shows non-blocking error banners.
- **`@Environment(\.showNowPlaying)`** is a custom environment key that any view can use to present the Now Playing sheet — this is how the shuffle button opens the player after starting playback.

### 7b. ViewModel Pattern

```bash
sed -n '1,80p' Lunara/Views/Library/LibraryGridViewModel.swift
```

```output
import Foundation
import Observation

@MainActor
protocol LibraryGridActionRouting: AlbumDetailActionRouting, AnyObject {
    func shuffleAllAlbums() async throws
}

extension AppCoordinator: LibraryGridActionRouting { }

@MainActor
@Observable
final class LibraryGridViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: LibraryGridActionRouting
    private let downloadManager: DownloadManagerProtocol?

    private var pendingArtworkAlbumIDs: Set<String> = []
    private var searchRequestID = 0
    private var searchTask: Task<Void, Never>?

    var albums: [Album] = []
    var searchQuery = "" {
        didSet {
            scheduleSearch()
        }
    }
    var queriedAlbums: [Album] = []
    var loadingState: LoadingState = .idle
    var artworkByAlbumID: [String: URL] = [:]
    var errorBannerState = ErrorBannerState()

    var filteredAlbums: [Album] {
        guard isSearchActive else {
            return albums
        }

        return queriedAlbums
    }

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: LibraryGridActionRouting,
        downloadManager: DownloadManagerProtocol? = nil
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
    }

    func loadInitialIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        await reloadCachedCatalog()
    }

    func refresh() async {
        do {
            _ = try await library.refreshLibrary(reason: .userInitiated)
            await reloadCachedCatalog()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    func playAlbum(_ album: Album) async {
        do {
            try await actions.playAlbum(album)
```

The ViewModel pattern is clean:

1. **Protocol-based routing**: `LibraryGridActionRouting` declares what coordinator actions the ViewModel needs. `AppCoordinator` conforms to this protocol (via an extension on the same line). The ViewModel only sees the protocol, never the coordinator directly.
2. **`@Observable`**: Swift's native observation — no Combine, no `@Published`. SwiftUI automatically re-renders when any observed property changes.
3. **`@MainActor`**: The entire ViewModel is main-actor-isolated, which is correct since it drives UI state.
4. **Injected dependencies**: `LibraryRepoProtocol`, `ArtworkPipelineProtocol`, and the action routing protocol are all injected, making the ViewModel fully testable with mocks.

## 8. System Integration

### 8a. NowPlayingBridge — Lock Screen & Control Center

The bridge syncs playback state to iOS's Now Playing system, providing lock screen controls and artwork.

```bash
sed -n '1,50p' Lunara/Music/NowPlaying/NowPlayingBridge.swift
```

```output
import Foundation
import MediaPlayer
import os
import UIKit

/// Bridges playback state to the iOS lock screen and Control Center via
/// MPNowPlayingInfoCenter and MPRemoteCommandCenter.
@MainActor
final class NowPlayingBridge {

    private let engine: PlaybackEngineProtocol
    private let queue: QueueManagerProtocol
    private let library: LibraryRepoProtocol
    private let artwork: ArtworkPipelineProtocol
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "NowPlayingBridge")

    /// Track ID for which we last published metadata, to avoid redundant lookups.
    private var lastPublishedTrackID: String?
    /// Whether the last publish included artwork successfully.
    private var lastPublishHadArtwork = false
    private var observationTask: Task<Void, Never>?
    private var artworkRetryTask: Task<Void, Never>?

    init(
        engine: PlaybackEngineProtocol,
        queue: QueueManagerProtocol,
        library: LibraryRepoProtocol,
        artwork: ArtworkPipelineProtocol
    ) {
        self.engine = engine
        self.queue = queue
        self.library = library
        self.artwork = artwork
    }

    deinit {
        observationTask?.cancel()
        artworkRetryTask?.cancel()
    }

    // MARK: - Public

    func configure() {
        registerRemoteCommands()
        startObserving()
    }

    // MARK: - Remote Commands

    private func registerRemoteCommands() {
```

```bash
sed -n '50,130p' Lunara/Music/NowPlaying/NowPlayingBridge.swift
```

```output
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.play()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.pause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.skipToNext()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.skipBack()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.engine.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Observation

    private func startObserving() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let trackID = self.engine.currentTrackID
                let state = self.engine.playbackState
                let elapsed = self.engine.elapsed
                let duration = self.engine.duration
                let queueIndex = self.queue.currentIndex

                await self.handleStateChange(
                    trackID: trackID,
                    state: state,
                    elapsed: elapsed,
                    duration: duration,
                    queueIndex: queueIndex
                )

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.engine.currentTrackID
                        _ = self.engine.playbackState
                        _ = self.engine.elapsed
                        _ = self.engine.duration
                        _ = self.queue.currentIndex
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Tracks the queue index from the last publish so we detect skip-back-to-same-track.
    private var lastPublishedQueueIndex: Int?

    private func handleStateChange(
        trackID: String?,
        state: PlaybackState,
        elapsed: TimeInterval,
        duration: TimeInterval,
        queueIndex: Int?
```

The NowPlayingBridge uses the same `withObservationTracking` pattern as the QueueManager, but wraps it in `withCheckedContinuation` to create an async loop. It watches five properties and re-publishes to `MPNowPlayingInfoCenter` whenever any change. Remote commands (play, pause, next, previous, seek) are wired directly back to the QueueManager.

### 8b. ScrobbleManager — Last.fm Integration

The scrobble manager watches playback and sends "now playing" updates and scrobbles to Last.fm following their standard rules.

```bash
sed -n '113,200p' Lunara/Music/Scrobbling/ScrobbleManager.swift
```

```output
    private func handleStateChange(
        trackID: String?,
        state: PlaybackState,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) async {
        guard LastFMSettings.load().isEnabled, authManager.isAuthenticated else { return }

        // Track play time accumulation
        updateAccumulatedPlayTime(newState: state)

        guard let trackID else {
            resetTrackState()
            return
        }

        if trackID != lastNowPlayingTrackID {
            // New track started
            resetTrackState()
            lastNowPlayingTrackID = trackID
            trackStartedAt = Date()
            lastPlaybackState = state
            lastStateChangeTime = Date()

            if state == .playing {
                await sendNowPlaying(trackID: trackID)
            }
            return
        }

        // Same track — check if we should send now playing (e.g. resumed after buffering)
        if state == .playing && lastPlaybackState != .playing && lastNowPlayingTrackID != nil {
            // Just started playing (was buffering/paused before)
            if trackStartedAt == nil {
                await sendNowPlaying(trackID: trackID)
            }
        }

        lastPlaybackState = state
        lastStateChangeTime = Date()

        // Check scrobble threshold
        if !hasScrobbled && state == .playing {
            await checkScrobbleThreshold(trackID: trackID, duration: duration)
        }
    }

    private func updateAccumulatedPlayTime(newState: PlaybackState) {
        if lastPlaybackState == .playing, let lastChange = lastStateChangeTime {
            accumulatedPlayTime += Date().timeIntervalSince(lastChange)
        }
    }

    private func checkScrobbleThreshold(trackID: String, duration: TimeInterval) async {
        guard duration > 30 else { return }

        let threshold = min(duration * 0.5, 240)
        guard accumulatedPlayTime >= threshold else { return }

        hasScrobbled = true
        await submitScrobble(trackID: trackID, duration: duration)
    }

    // MARK: - API Calls

    private func sendNowPlaying(trackID: String) async {
        guard let sessionKey = authManager.sessionKey else { return }

        do {
            guard let track = try await library.track(id: trackID) else { return }
            let album = try? await library.album(id: track.albumID)

            try await client.updateNowPlaying(
                artist: track.artistName,
                track: track.title,
                album: album?.title,
                duration: Int(track.duration),
                sessionKey: sessionKey
            )
            logger.info("Now playing: \(track.title, privacy: .public) by \(track.artistName, privacy: .public)")
        } catch {
            logger.error("Failed to update now playing: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func submitScrobble(trackID: String, duration: TimeInterval) async {
        guard let timestamp = trackStartedAt.map({ Int($0.timeIntervalSince1970) }) else { return }

```

The scrobbling rules follow the Last.fm standard precisely:

- **Now Playing**: Sent immediately when a new track starts playing.
- **Scrobble threshold**: The track must have accumulated play time ≥ 50% of duration OR ≥ 4 minutes (whichever is less). Tracks under 30 seconds are never scrobbled.
- **Accumulated play time**: Only `.playing` state counts — buffering and paused time are excluded. This prevents inflated counts from network hiccups.
- **Offline queue**: If a scrobble API call fails, it's saved to a persistent `ScrobbleQueue` and retried in batches later.

## 9. Offline Support

Lunara can download albums for offline playback. The system has three parts: `OfflineStore` (database tracking), `DownloadManager` (orchestration), and the AppRouter's `resolveURL` method that transparently serves local files.

```bash
sed -n '13,55p' Lunara/Library/Offline/OfflineStore.swift
```

```output
    func localFileURL(forTrackID trackID: String) async throws -> URL? {
        let targetID = trackID
        let record = try await dbQueue.read { db in
            try OfflineTrackRecord.fetchOne(db, key: targetID)
        }

        guard let record else { return nil }

        let fileURL = offlineDirectory.appendingPathComponent(record.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        // Stale row: file is missing on disk — clean up
        let staleID = record.trackID
        try await dbQueue.write { db in
            _ = try OfflineTrackRecord.deleteOne(db, key: staleID)
        }
        return nil
    }

    func offlineStatus(forAlbum albumID: String, totalTrackCount: Int) async throws -> OfflineAlbumStatus {
        let targetAlbumID = albumID
        let downloadedCount = try await dbQueue.read { db -> Int in
            try OfflineTrackRecord
                .filter(Column("albumID") == targetAlbumID)
                .fetchCount(db)
        }

        if downloadedCount == 0 {
            return .notDownloaded
        } else if downloadedCount >= totalTrackCount {
            return .downloaded
        } else {
            return .partiallyDownloaded(downloadedCount: downloadedCount, totalCount: totalTrackCount)
        }
    }

    func saveOfflineTrack(_ offlineTrack: OfflineTrack) async throws {
        let record = OfflineTrackRecord(model: offlineTrack)
        try await dbQueue.write { db in
            try record.save(db)
        }
```

The offline system is self-healing: `localFileURL` checks that the file actually exists on disk. If the database says a track is downloaded but the file is missing (e.g., iOS purged it for storage), it cleans up the stale record and returns `nil`, causing the router to fall back to streaming. No user intervention needed.

## 10. Error Handling

Errors flow through a protocol-based system where every error provides a human-readable message, displayed via non-blocking banners.

```bash
cat Lunara/Shared/Errors/LunaraError.swift
```

```output
import Foundation

// MARK: - LunaraError Protocol

/// Protocol for all Lunara errors to provide consistent user-facing messages.
/// Each domain defines its own error enum conforming to this protocol.
protocol LunaraError: Error {
    /// Human-readable error message suitable for display in UI
    var userMessage: String { get }
}

// MARK: - LibraryError

/// Errors originating from the Library domain (Plex API, storage, auth, etc.)
enum LibraryError: LunaraError, Equatable {
    /// Plex server is unreachable (network down, wrong URL, server offline)
    case plexUnreachable

    /// Authentication token has expired or is invalid
    case authExpired

    /// Local database is corrupted or unreadable
    case databaseCorrupted

    /// API request failed with specific HTTP error
    case apiError(statusCode: Int, message: String)

    /// Failed to parse response from Plex server
    case invalidResponse

    /// Requested resource not found (album, track, artist, etc.)
    case resourceNotFound(type: String, id: String)

    /// Network request timed out
    case timeout

    /// Generic library operation failed
    case operationFailed(reason: String)

    var userMessage: String {
        switch self {
        case .plexUnreachable:
            return "Cannot reach your Plex server. Check your connection."
        case .authExpired:
            return "Your session has expired. Please sign in again."
        case .databaseCorrupted:
            return "Local library data is corrupted. Try refreshing your library."
        case .apiError(let statusCode, let message):
            return "Plex error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Received unexpected data from Plex. Try refreshing."
        case .resourceNotFound(let type, _):
            return "\(type.capitalized) not found in your library."
        case .timeout:
            return "Request timed out. Check your connection."
        case .operationFailed(let reason):
            return "Library error: \(reason)"
        }
    }
}

// MARK: - MusicError

/// Errors originating from the Music domain (playback, streaming, audio session, etc.)
enum MusicError: LunaraError, Equatable {
    /// Audio stream failed to load or buffer
    case streamFailed(reason: String)

    /// Requested track is unavailable for playback
    case trackUnavailable

    /// Audio session configuration failed
    case audioSessionFailed

    /// Playback was interrupted and could not resume
    case interruptionFailed

    /// Invalid track URL provided
    case invalidURL

    /// Queue operation failed
    case queueOperationFailed(reason: String)

    /// Playback engine is in an invalid state for the requested operation
    case invalidState(reason: String)

    var userMessage: String {
        switch self {
        case .streamFailed(let reason):
            return "Stream failed: \(reason)"
        case .trackUnavailable:
            return "This track is not available for playback."
        case .audioSessionFailed:
            return "Could not initialize audio. Try restarting the app."
        case .interruptionFailed:
            return "Playback was interrupted and could not resume."
        case .invalidURL:
            return "Invalid audio source. Try refreshing this track."
        case .queueOperationFailed(let reason):
            return "Queue error: \(reason)"
        case .invalidState(let reason):
            return "Playback error: \(reason)"
        }
    }
}
```

Every error in the app conforms to `LunaraError` and provides a `userMessage`. There are no raw `Error.localizedDescription` strings reaching the UI. The two domain error enums (`LibraryError` and `MusicError`) cover every failure mode — from network issues to corrupted databases to audio session failures.

These are displayed via `ErrorBannerState`, a simple observable that shows a non-blocking banner at the top of the screen. Errors are never swallowed silently and never shown as blocking alert dialogs.

## 11. End-to-End Flow: "Play This Album"

To tie everything together, let's trace what happens when a user taps the play button on an album detail screen:

1. **`AlbumDetailView`** calls `viewModel.playAlbum()`
2. **`AlbumDetailViewModel`** calls `actions.playAlbum(album)` (the `ActionRouting` protocol)
3. **`AppCoordinator`** (conforming to the protocol) calls `appRouter.playAlbum(album)`
4. **`AppRouter.playAlbum`**:
   - Fetches tracks from `LibraryRepo` (cache-first)
   - For each track, calls `resolveURL` (offline file → streaming URL fallback)
   - Creates `[QueueItem]` with trackID + URL pairs
   - Calls `queueManager.playNow(items)`
5. **`QueueManager.playNow`**:
   - Sets the queue items and `currentIndex = 0`
   - Calls `engine.play(url:trackID:)`
6. **`AVQueuePlayerEngine.play`**:
   - Configures the audio session for `.playback`
   - Transitions to `.buffering`
   - Starts an 8-second timeout
   - Hands the URL to `AVQueuePlayerDriver`
   - AVQueuePlayer loads the stream → transitions to `.playing`
7. **`NowPlayingBridge`** observes the new `currentTrackID`:
   - Looks up track metadata from LibraryRepo
   - Loads artwork from ArtworkPipeline
   - Publishes to `MPNowPlayingInfoCenter` (lock screen)
8. **`ScrobbleManager`** observes `.playing`:
   - Sends "now playing" to Last.fm
   - Starts accumulating play time
   - At 50% or 4 minutes, sends the scrobble

When the track ends, step 5 repeats — the engine signals `.idle`, the queue advances, and the next track plays automatically.

## 12. Project Structure Summary

```bash
find Lunara -type f -name '*.swift' | sed 's|/[^/]*$||' | sort -u | head -30
```

```output
Lunara
Lunara/App
Lunara/App/Intents
Lunara/Library/API
Lunara/Library/Artwork
Lunara/Library/Auth
Lunara/Library/Offline
Lunara/Library/Repo
Lunara/Library/Store
Lunara/Music/Engine
Lunara/Music/NowPlaying
Lunara/Music/Queue
Lunara/Music/Scrobbling
Lunara/Music/Session
Lunara/Router
Lunara/Shared/Errors
Lunara/Shared/Models
Lunara/Views/Album
Lunara/Views/Artist
Lunara/Views/Collection
Lunara/Views/Components
Lunara/Views/Debug
Lunara/Views/Library
Lunara/Views/NowPlaying
Lunara/Views/Settings
Lunara/Views/SignIn
```

```bash
echo 'Swift files:' && find Lunara -name '*.swift' | wc -l && echo 'Test files:' && find LunaraTests -name '*.swift' 2>/dev/null | wc -l && echo 'Lines of Swift:' && find Lunara LunaraTests -name '*.swift' 2>/dev/null -exec cat {} + | wc -l
```

```output
Swift files:
     100
Test files:
      57
Lines of Swift:
   24656
```

The directory structure mirrors the architecture cleanly:

- **`App/`** — Coordinator, app lifecycle, Siri intents
- **`Library/`** — Everything Plex: API client, auth, SQLite store, artwork pipeline, offline downloads
- **`Music/`** — Everything audio: playback engine, queue, audio session, lock screen, scrobbling
- **`Router/`** — The single bridge between Library and Music
- **`Shared/`** — Models and error types used by both domains
- **`Views/`** — SwiftUI views and their ViewModels, organized by screen

~100 source files, ~57 test files, ~25k lines of Swift. The two-domain architecture keeps complexity manageable — you can work on the playback engine without knowing anything about Plex, or add a new metadata field without touching audio code. The AppRouter is the only seam between them.
