# Lunara

A personal iOS music player for a Plex library. Built for rediscovery, album-first listening, and emotional context — not for general Plex client parity.

This is a single-user tool. Broad market appeal is not a goal.

---

## How This Document Works

This README is the **constitution** for this project. Every AI coding session should read this file before writing any code. It defines the architecture, the module boundaries, the build order, and the rules of engagement.

If something isn't in this document, it's not in scope yet. If a task would violate a boundary defined here, stop and ask.

---

## Product Goal

**One sentence:** Let me press play and hear my music — reliably, quickly, and with the feeling that my library is a living, personal space.

**Prioritized outcomes:**

1. Playback is fast and never broken.
2. My library feels explorable — shuffle, collections, and rediscovery over linear browsing.
3. Albums are the primary unit of everything — discovery, playback, notes, curation.

---

## Project Status

- **Phase 1 (Shared Types + Plex Connectivity):** Complete
- **Phase 2 (Playback Engine + Queue Manager):** Complete
- **Phase 3 (Library Domain Core):** Complete
- **Phase 4 (UI Shell):** Complete
- **Phase 5 (Collections + Artists):** Complete
- **Phase 6 (Lock Screen + Remote Controls):** Complete
- **Last.fm Scrobbling:** Complete
- **Last verified milestone:** Last.fm scrobbling verified on February 22, 2026.

---

## Core Philosophy

### The Library as a Digital Garden

The music library is a living space to be tended, not a static catalog to be browsed. Albums surface unexpectedly. Rediscovery matters as much as first discovery. Shuffle is a primary interaction, not a secondary feature.

### Albums First

Albums are the canonical unit. Track-level interaction exists, but discovery, playback context, notes, theming, collections, and curation all revolve around albums.

### Plex as Source of Truth

Plex is authoritative for library structure, metadata, ratings, artwork, and audio files. This app reads Plex metadata, writes star ratings back (online only), and never deletes media or modifies library structure. Personal data (notes, deletion marks, themes, garden todos) lives outside Plex on a separate server, introduced in a later phase.

---

## Technical Context

- **Plex server:** Serves audio via direct play (no transcoding).
- **Audio format:** MP3.
- **Library size:** 2,000+ albums. Requires pagination or lazy loading.
- **iOS target:** iPhone 15 Pro, iOS 17+.
- **Language:** Swift. SwiftUI preferred; UIKit acceptable where it simplifies implementation.
- **Local storage:** GRDB (SQLite wrapper).
- **Background audio:** The app requires the `UIBackgroundModes` audio entitlement in Info.plist. This must be configured from the very first phase that involves playback. Audio must continue when the app is backgrounded or the screen is locked.
- **No external backend for initial phases.** A Rails API will be introduced later for notes, deletion queue, and personal data. It will be specced when we get there.

---

## Architecture: Two Domains and a Coordinator

The app is split into two domains, a coordinator that bridges them, and a shared type layer. Each domain owns its own storage, state, and internal logic. Domains never reach into each other's internals.

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                      │
│        (Library, Album, Artist, Now Playing, Settings)  │
└──────────────────────────┬──────────────────────────────┘
                           │
                     ┌─────▼──────┐
                     │ AppRouter  │
                     │            │
                     │ Translates │
                     │ user       │
                     │ intents    │
                     │ into       │
                     │ cross-     │
                     │ domain     │
                     │ operations │
                     └──┬─────┬──┘
                        │     │
         ┌──────────────▼┐   ┌▼──────────────────┐
         │ Music Domain  │   │  Library Domain    │
         │               │   │                    │
         │ PlaybackEngine│   │  PlexAPIClient     │
         │ QueueManager  │   │  AuthManager       │
         │ NowPlaying    │   │  LibraryStore      │
         │   Bridge      │   │  (GRDB/SQLite)     │
         │ Scrobbling    │   │                    │
         │ AudioSession  │   │                    │
         │               │   │  Albums            │
         │               │   │  Collections       │
         │               │   │  Artists            │
         │               │   │  Artwork Pipeline  │
         │               │   │                    │
         │               │   │  [Future:]         │
         │               │   │  Notes             │
         │               │   │  Deletion Marks    │
         │               │   │  Themes            │
         │               │   │  Garden Todos      │
         │               │   │  Offline Downloads │
         └───────────────┘   └────────────────────┘
                        │     │
                   ┌────▼─────▼────┐
                   │ Shared Types  │
                   │               │
                   │ Album         │
                   │ Track         │
                   │ Artist        │
                   │ Collection    │
                   │ PlaybackState │
                   │ LunaraError   │
                   └───────────────┘
```

---

### Shared Types

Plain Swift structs and enums with no behavior and no dependencies. Both domains and all views can use them.

```swift
// Illustrative, not final signatures.

struct Album: Identifiable {
    let plexID: String
    let title: String
    let artistName: String
    let year: Int?
    // ...
}

struct Track: Identifiable {
    let plexID: String
    let albumID: String
    let title: String
    let trackNumber: Int
    let duration: TimeInterval
    // ...
}

struct Artist: Identifiable {
    let plexID: String
    let name: String
    let sortName: String?
    // ...
}

struct Collection: Identifiable {
    let plexID: String
    let title: String
    // ...
}

enum PlaybackState {
    case idle
    case buffering
    case playing
    case paused
    case error(String)
}
```

`PlaybackState` includes `buffering` because there is a real delay between tapping play on a streaming URL and hearing audio. The UI must distinguish "loading" from "paused" — otherwise the app looks frozen. Every screen that shows playback state must handle `buffering` explicitly (e.g., a loading indicator on the play button, a spinner on the now playing bar).

**Rules for shared types:**
- Structs and enums only. No classes, no protocols, no logic beyond computed properties.
- No GRDB conformances here. The Library domain handles its own database mapping internally.
- If you're adding a method to a shared type, it probably belongs in a domain instead.

---

### Error Strategy

Errors are **never swallowed silently.** Every failure the user might notice must surface in the UI.

**Principles:**
- Each domain defines its own error enum (e.g., `LibraryError`, `MusicError`). These enums conform to a shared `LunaraError` protocol so the UI can display them consistently.
- Errors are propagated, not caught-and-ignored. If a function can fail, it throws or returns a Result. No `try?` with silent nil.
- The UI has **one consistent pattern** for showing errors: a non-blocking banner/toast at the top of the screen. Not an alert dialog (those block interaction). The banner shows a short message and dismisses automatically or on tap.
- Playback errors (stream failure, network loss) are surfaced through `PlaybackState.error(String)`. The now playing UI reacts to this state.
- Network errors during library refresh show the banner but leave cached data visible. The app is always usable with stale data.

```swift
// Illustrative
protocol LunaraError: Error {
    var userMessage: String { get }
}

enum LibraryError: LunaraError {
    case plexUnreachable
    case authExpired
    case databaseCorrupted
    // ...
    var userMessage: String { /* human-readable */ }
}

enum MusicError: LunaraError {
    case streamFailed(String)
    case trackUnavailable
    // ...
    var userMessage: String { /* human-readable */ }
}
```

---

### Library Domain

Owns everything about *what music exists and what the user thinks about it.* This is where the digital garden grows.

**Components:**

**AuthManager**
- Owns the Plex auth token lifecycle.
- Token is stored in **Keychain** (not UserDefaults — it's a credential).
- Handles the Plex pin-based OAuth sign-in flow.
- Provides a `validToken() async throws -> String` method that returns a current token or triggers re-auth.
- PlexAPIClient calls `validToken()` before every request. AuthManager is responsible for knowing if the token is stale.
- On token expiry: surfaces `LibraryError.authExpired` so the UI can prompt re-sign-in.

**PlexAPIClient**
- All HTTP communication with Plex.
- Accepts an `AuthManager` dependency (injected, not a singleton).
- Typed methods: `fetchAlbums()`, `fetchTracks(forAlbum:)`, `fetchCollections()`, `fetchArtists()`, `streamURL(forTrack:) -> URL`, `writeRating(album:rating:)`.
- Stateless beyond the auth dependency. No caching, no persistence.
- Returns shared types.
- All methods throw `LibraryError` on failure.

**LibraryStore (GRDB)**
- Single SQLite database for all Library domain persistence.
- Stores album/track/artist/collection metadata as cached copies of Plex data.
- Stores artwork file paths (artwork files live on disk, store tracks paths only).
- Exposes async read/write methods.
- Handles album deduplication logic (merging split track groups from Plex).
- Pagination support for the 2,000+ album library grid.
- No networking. Receives data from PlexAPIClient via LibraryRepo.

**LibraryRepo**
- The public API surface of the Library domain. Views and the coordinator talk to this, not directly to PlexAPIClient or LibraryStore.
- On launch: serves cached data from LibraryStore immediately.
- On pull-to-refresh: fetches from Plex, diffs against cache, updates LibraryStore. On network failure, surfaces error via banner but keeps cached data visible.
- Provides: `albums(page:)`, `album(id:)`, `tracks(forAlbum:)`, `collections()`, `artists()`, `artist(id:)`, `streamURL(forTrack:) -> URL`, etc.

**Artwork Pipeline**
- Two sizes: **thumbnail** (grid, ~300px) and **full** (detail/now playing, ~1024px).
- On-disk cache with LRU eviction (250 MB cap).
- Loading order: disk cache (instant) → Plex fetch (async, with placeholder shown).
- Thumbnails are aggressively preloaded during library sync. Full-size loads on demand when album detail or now playing opens.
- The library grid must **never** block on network for artwork that's been seen before. If it's not cached, show a placeholder and load async.
- This is a dedicated component, not part of LibraryStore. It manages its own file storage and eviction.

**Future additions (not yet — listed to show where they'll live):**
- NotesStore: album session notes, synced to Rails API.
- DeletionStore: marked-for-deletion albums, synced to Rails API.
- ThemeStore: personal memory themes, era/genre rules.
- GardenStore: todo/gardening actions on albums, tracks, artists.
- OfflineStore: download state, verified files, storage accounting.

Each gets its own store and sync client when the time comes. They live in the Library domain because they're about *what the user thinks about their library*, not about audio playback.

---

### Music Domain

Owns everything about *playing audio.* Deliberately small. Should rarely change once solid.

**Components:**

**PlaybackEngine**
- Owns `AVQueuePlayer` (not plain AVPlayer — this enables preloading).
- Protocol-based for future swap (e.g., AVAudioEngine for gapless/crossfade).
- Core methods: `play(url:trackID:)`, `pause()`, `resume()`, `seek(to:)`, `stop()`.
- **Preloading:** exposes `prepareNext(url:trackID:)`. When called, the engine creates an `AVPlayerItem` for the next track and appends it to the `AVQueuePlayer`. This eliminates dead air between tracks. QueueManager calls `prepareNext` proactively whenever the queue changes or a track starts playing.
- Reports observable state: `playbackState` (including `.buffering`), `elapsed`, `duration`, `currentTrackID`.
- Handles stream errors and network interruptions: transitions to `.error(message)`, never plays silence.
- Does **not** know about queues, albums, or collections. It plays URLs and reports state.

```swift
protocol PlaybackEngineProtocol: Observable {
    var playbackState: PlaybackState { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var currentTrackID: String? { get }

    func play(url: URL, trackID: String)
    func prepareNext(url: URL, trackID: String)
    func pause()
    func resume()
    func seek(to time: TimeInterval)
    func stop()
}
```

The `buffering` state is entered when `play()` or `prepareNext()` is called and the `AVPlayerItem` hasn't started playback yet. The engine observes `AVPlayerItem.status` and `AVPlayer.timeControlStatus` to transition between `buffering`, `playing`, and `error`.

**QueueManager**
- Ordered list of tracks to play.
- Supports: play now, play next, play later (album and track level).
- Observes PlaybackEngine for "track ended" → advances to next track and calls `play()` on the engine.
- **Proactive preloading:** whenever a track starts playing or the queue changes, QueueManager calls `prepareNext()` on the engine with the next track's URL. This means the engine always has the next track buffered before the current one ends.
- Persists queue separately from LibraryStore (its own lightweight file or GRDB database).
- On relaunch: restores queue and position, waits for explicit play.
- Shuffle logic lives here when built (Phase 9).

**NowPlayingBridge**
- Updates MPNowPlayingInfoCenter (track, artist, album, artwork, elapsed, duration).
- Registers MPRemoteCommandCenter handlers (play, pause, next, previous).
- Observes PlaybackEngine + QueueManager.
- ~100 lines of iOS system integration glue.

**Last.fm Scrobbling**
- `LastFMClient`: API client for Last.fm REST endpoints (`auth.getToken`, `auth.getSession`, `track.updateNowPlaying`, `track.scrobble`). Signs requests with MD5 hash per Last.fm spec. Protocol-based (`LastFMClientProtocol`). API key and shared secret loaded from `LocalConfig.plist`.
- `LastFMAuthManager`: Manages Last.fm session key (stored in Keychain via `KeychainHelper`). Web auth flow: fetches token → opens Safari → user approves → app exchanges token on foreground return. Exposes `isAuthenticated`, `username`, `authenticate()`, `signOut()`.
- `ScrobbleManager`: Observes PlaybackEngine (same `withObservationTracking` loop as `NowPlayingBridge`). Sends "now playing" on track start. Scrobbles when elapsed >= 50% of duration or >= 4 minutes (Last.fm rule). Skips tracks < 30 seconds. Only counts `.playing` time (not buffering/paused).
- `ScrobbleQueue`: Actor-based offline queue. Persists pending scrobbles to JSON file. On scrobble failure, enqueues. Retries in batches of 50 on next successful API call or app launch.
- `LastFMSettings`: UserDefaults toggle for enabling/disabling scrobbling independently of auth state.
- Settings UI: Last.fm section with connected status, username, sign in/out button, scrobbling toggle.

**AudioSession**
- Configures AVAudioSession (category: `.playback`, mode: `.default`).
- Handles interruptions (phone calls, Siri) — pauses on interruption, optionally resumes after.
- Must be configured before the first `play()` call.
- Small and self-contained.

---

### Track URL Resolution

When the user taps play, something needs to figure out *which URL* to hand to the Music domain. Today, that's always a Plex streaming URL. In the future (Phase 8, offline), it might be a local file URL.

This resolution lives in the **AppRouter** — it's a cross-domain concern.

```swift
// Illustrative. Today this is trivial; it grows when offline is added.
func resolveURL(for track: Track) -> URL {
    // Phase 8 will add: if let localURL = offlineStore.localFile(for: track) { return localURL }
    return library.streamURL(for: track)
}
```

By naming this now, we avoid the Phase 8 problem of "where does offline/online switching go?" It goes in the router's resolve method. The Music domain never knows or cares whether the URL is local or remote.

---

### AppRouter (The Coordinator)

Translates user intents into cross-domain operations. The only place Library and Music domains interact.

```swift
// Illustrative, not final.
class AppRouter {
    let library: LibraryRepo
    let queue: QueueManager

    func resolveURL(for track: Track) -> URL {
        // Future: check offline store first
        return library.streamURL(for: track)
    }

    func playAlbum(_ album: Album) async {
        let tracks = await library.tracks(forAlbum: album.plexID)
        let items = tracks.map { QueueItem(track: $0, url: resolveURL(for: $0)) }
        queue.playNow(items)
    }

    func shuffleCollection(_ collection: Collection) async {
        let albums = await library.albums(inCollection: collection.plexID)
        var tracks: [Track] = []
        for album in albums {
            tracks.append(contentsOf: await library.tracks(forAlbum: album.plexID))
        }
        let items = tracks.map { QueueItem(track: $0, url: resolveURL(for: $0)) }
        queue.shuffleAndPlay(items)
    }

    func queueAlbumNext(_ album: Album) async {
        let tracks = await library.tracks(forAlbum: album.plexID)
        let items = tracks.map { QueueItem(track: $0, url: resolveURL(for: $0)) }
        queue.playNext(items)
    }
}
```

**Rules for the AppRouter:**
- The **only** place Library and Music domains interact.
- Owns track URL resolution (streaming vs. local file).
- No business logic. Translates intents: fetch from Library, resolve URLs, hand to Music.
- If it grows beyond ~200 lines, split into sub-routers (`PlaybackRouter`, `DownloadRouter`).
- Views send actions through the router. Views observe domain state directly for display.

---

### What Talks to What

| Component | Can talk to | Cannot talk to |
|---|---|---|
| Views | AppRouter (actions), LibraryRepo (read), Music Domain (observe) | PlexAPIClient, LibraryStore, PlaybackEngine (actions) |
| AppRouter | LibraryRepo, QueueManager | PlexAPIClient, LibraryStore, PlaybackEngine directly |
| LibraryRepo | PlexAPIClient, LibraryStore, Artwork Pipeline | Music Domain |
| QueueManager | PlaybackEngine, its own persistence | Library Domain |
| PlaybackEngine | Nothing. It is called and observed. | Everything |
| NowPlayingBridge | PlaybackEngine (observe), QueueManager (observe), LibraryRepo (read metadata), ArtworkPipeline (read artwork) | — |
| ScrobbleManager | PlaybackEngine (observe), LibraryRepo (read metadata), LastFMClient, LastFMAuthManager, ScrobbleQueue | — |
| AuthManager | Keychain | Everything else (it's injected into PlexAPIClient) |

---

## Build Order

Sequential. Each phase fully working and verified on device before the next begins.

### Phase 1: Shared Types + Plex Connectivity

**Goal:** Define the data language and prove Plex connectivity.
**Status:** Complete.

**Build:**
- Shared types: `Album`, `Track`, `Artist`, `Collection`, `PlaybackState` (with `buffering`), `LunaraError` protocol, `LibraryError`, `MusicError`.
- `AuthManager`: pin-based OAuth, Keychain token storage, `validToken()`.
- `PlexAPIClient`: `fetchAlbums()`, `fetchTracks(forAlbum:)`, `streamURL(forTrack:)`.
- Sign-in screen (functional, not styled).
- Debug quick sign-in via `LocalConfig.plist`.
- `UIBackgroundModes` audio entitlement configured in Info.plist.

**Acceptance:** Sign in. App logs album list to console. Token persists across app restart (Keychain). Background audio entitlement is present in the built app.

**AI scope:** Shared types (one session). AuthManager (one session). PlexAPIClient protocol then implementation (one session).

---

### Phase 2: Playback Engine + Queue Manager

**Goal:** Press play on an album, hear it front to back with seamless track transitions.
**Status:** Complete (implemented + device-verified on February 17, 2026).

These two are built together because the PlaybackEngine needs someone to drive track advancement and preloading, and testing sequential playback without a queue is artificial. However, they are still **separate modules with separate files and separate tests.** Building together means they're in the same phase, not the same file.

**Build:**
- `AudioSession` configuration (category `.playback`, interruption handling).
- `PlaybackEngineProtocol` + `AVQueuePlayer` implementation.
  - `play(url:trackID:)`, `prepareNext(url:trackID:)`, `pause()`, `resume()`, `seek(to:)`, `stop()`.
  - Observable state including `.buffering` transitions.
  - Network interruption → `.error` state, never silent playback.
- `QueueManager`: play now, play next, play later.
  - Observes PlaybackEngine "track ended" → auto-advance.
  - Proactive preloading: on track start or queue change, calls `prepareNext()` with the next track's URL.
  - Persists queue (separate from LibraryStore — own file or lightweight DB).
  - On relaunch: restores queue and position, waits for explicit play.
- Minimal `AppRouter` with `resolveURL(for:)` and `playAlbum()` wired up.
- Test UI: a single screen that lists hardcoded tracks from one album with a play button. Enough to verify playback, track transitions, preloading, pause/resume, skip, queue persistence, and background audio.

**Acceptance:**
- Play an album front to back. Track transitions are seamless (no dead air gap).
- Skip a track — next track starts quickly (preloaded).
- Kill wifi mid-track — app shows error state, doesn't play silence.
- Lock phone — audio continues playing.
- Force-quit, reopen — queue is intact, app waits for explicit play.
- UI shows buffering state when a track is loading.

**Completion evidence (February 17, 2026):**
- Full project test command passes: `xcodebuild test -project /Users/timbornholdt/Repos/Lunara/Lunara.xcodeproj -scheme Lunara -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`.
- Manual device QA confirmed seamless transitions, skip behavior, playback error handling, lock-screen/background playback continuity, and queue restore behavior.

**AI scope:** AudioSession (tiny, one session). PlaybackEngine protocol → get approval → implementation (one session). QueueManager protocol → get approval → implementation (one session). Wiring + test UI (one session). Four sessions total.

---

### Phase 3: Library Domain Core

**Goal:** Cached browsing with pull-to-refresh.
**Status:** Complete (implemented and acceptance-hardened on February 17, 2026).

**Build:**
- `LibraryStore` (GRDB): schema for albums, tracks, artists, collections, artwork paths.
- `LibraryRepo`: cache-on-refresh, serve-from-cache-on-launch, pagination.
- Album deduplication (merging split track groups from Plex).
- `Artwork Pipeline`: two-size caching (thumbnail + full), LRU eviction (250 MB cap), disk-first loading with async Plex fallback and placeholders.
- Error handling: network failures during refresh show banner, cached data stays visible.

**Acceptance:** Launch → library loads instantly from cache. Pull-to-refresh updates from Plex. 2,000+ albums scroll smoothly with no artwork loading jank (placeholders for uncached, instant for cached). Kill network during refresh → error banner, cached data still works.

**Completion evidence (February 17, 2026):**
- Full project test command passes: `xcodebuild test -project /Users/timbornholdt/Repos/Lunara/Lunara.xcodeproj -scheme Lunara -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`.
- Dependency chain wiring complete: `AppCoordinator` composes `LibraryRepo + LibraryStore + ArtworkPipeline` with protocol-based injection.
- Refresh path hardened: relative Plex artwork paths are resolved to authenticated absolute URLs; metadata refresh completes without waiting on artwork warmup; cached fallback behavior remains intact when refresh fails.

**AI scope:** GRDB schema (one session). LibraryRepo (one session). Artwork pipeline (one session). Three sessions minimum.

---

### Phase 4: UI Shell

**Goal:** Browse and play. Functional and styled.
**Status:** Complete (implemented and verified on February 20, 2026).

**Build:**
- Library grid (paginated, album art + title, artwork pipeline integrated). ✅
- Album detail (track list, play/queue actions via AppRouter). ✅
- Now playing bar (floating, current track, play/pause, buffering indicator). ✅
- Now playing screen (slides up, dismiss pull-down, artwork, controls, buffering state). ✅
- Error banner component (consistent across all screens). ✅
- Long-press queue menus on albums and tracks. ✅
- Visual design language applied (Playfair, linen, pill buttons). ✅

**What was built:**
- Full visual design system: semantic color tokens, Playfair Display typography, linen background texture, pill button component, tab bar theming — all in `Views/Components/`.
- Error banner: non-blocking toast at top of screen, auto-dismiss, accessible, integrated into all current views.
- Library grid: adaptive grid layout, artwork with async loading and placeholders, search with debounce, pull-to-refresh, loading/empty/error states.
- Album detail: hero card with artwork + metadata, track list with async loading, genre/style/mood tags, context menus for queue operations on albums and tracks.
- AppRouter: full playback and queue wiring (play now, play next, play later at album and track level).
- Now Playing Bar: floating compact strip above the iOS 26 Liquid Glass tab bar. Shows artwork thumbnail, track title + artist (Playfair Display), play/pause/buffering/error states. Tapping opens full Now Playing screen. Hides when queue is empty.
- Now Playing Screen: full-screen sheet with large artwork, track info (Playfair Display), seek bar, transport controls (previous/play-pause/next), up-next queue, artwork-derived color palette, star rating display for rated albums, pull-down dismiss gesture.

**Acceptance:** Full flow: scroll library → tap album → play → now playing bar shows track with buffering then playing → full screen → skip/pause/resume. Errors show as banners. Looks like Lunara.

**AI scope:** Error banner component (one session). Each screen (separate sessions). Router wiring (one session). Styling pass (one session).

---

### Phase 5: Collections + Artists

**Goal:** Browse by collection and by artist.
**Status:** Complete (implemented and verified on February 21, 2026).

**Build:**
- Collections tab with artwork. "Current Vibes" and "The Key Albums" pinned top. ✅
- Collection detail: albums, hero header, Play / Shuffle All. ✅
- Artists tab: alphabetical, artist detail with hero art, summary, genre pills, albums by year. ✅
- Tab bar: Collections | All Albums | Artists. ✅
- Naive shuffle (random order, no anti-annoyance rules yet). ✅

**Acceptance:** Browse collections, browse artists, start playback from any view.

**AI scope:** Collections and artists as separate sessions.

---

### Phase 6: Lock Screen + Remote Controls

**Goal:** Control playback without opening the app.
**Status:** Complete (implemented and verified on February 21, 2026).

**Build:**
- `NowPlayingBridge`: MPNowPlayingInfoCenter metadata + artwork. ✅
- MPRemoteCommandCenter: play, pause, next, previous, scrub. ✅
- Artwork retry logic for uncached artwork on first play. ✅
- Queue exhaustion handling: engine stops and lock screen clears when album ends. ✅

**What was built:**
- `NowPlayingBridge` in `Lunara/Music/NowPlaying/`: observes PlaybackEngine and QueueManager via `withObservationTracking`, publishes track metadata (title, artist, album, duration) and playback position (elapsed + playbackRate for iOS-interpolated progress) to `MPNowPlayingInfoCenter`. Registers `MPRemoteCommandCenter` handlers for play, pause, next, previous, and scrub-to-position.
- Artwork: fetches full-size album artwork via ArtworkPipeline. If artwork isn't cached yet (first play of an album), retries up to 3 times with exponential backoff (2s/4s/6s). Guards against stale artwork overwrites on rapid track changes.
- Queue index tracking: detects skip-back-to-same-track by observing `queue.currentIndex` changes, not just trackID changes. Ensures metadata and artwork re-publish on every track transition.
- Queue exhaustion fix in `QueueManager`: when the last track in the queue finishes, the engine is stopped, `currentIndex` is nilled, and persisted state is reset. This clears the lock screen and the in-app now playing bar.

**Acceptance:** Lock phone. Correct track on lock screen with artwork. Tap next — correct track plays. Phone call pauses, resumes after. Album ends — lock screen clears.

**AI scope:** One session.

---

### Phase 7: Offline Playback

**Goal:** Download albums for offline listening.

**Build:**
- `OfflineStore` in Library domain: download state, verified file paths, storage accounting.
- Download button on album detail.
- Download collection (skip already-downloaded).
- Complete-only downloads (incomplete → removed).
- `AppRouter.resolveURL()` updated: check local file first, fall back to streaming.
- Manage downloads in settings.
- Storage cap (128 GB default), LRU eviction, Wi-Fi-only toggle.

**Acceptance:** Download on Wi-Fi. Airplane mode. Play. Works. Partial downloads never appear available. Stream URL fallback works when not downloaded.

**AI scope:** OfflineStore (one session). Download engine (one session). resolveURL update + UI (one session). Three sessions minimum.

---

### Future Phases (Not Scoped — Do Not Build)

- **Wikipedia Context:** Album history, cached locally.
- **Deep Linking:** Action button → random album instantly.
- **Digital Gardening ("The Weeder"):** Library maintenance todos.
	- **Personal Notes:** Album session notes → Rails API.
	- **Marked for Deletion:** Curation workflow → Rails API + web dashboard.
- **CarPlay:** Browse, shuffle, now playing.
- **Theming:** Artwork colors, era/genre, personal memory themes.
- **Gapless / Crossfade:** AVAudioEngine migration.

---

## Visual Design Direction

Warm, textured, personal. More vinyl shelf than streaming app.

### Typography
- **Display/headings:** Playfair Display.
- **Body/controls:** Playfire Display.

### Color + Texture
- **Background:** Linen texture, generated programmatically, adapts to theme.
- **Palette:** Warm neutrals. Accent colors from album artwork.
- **Semantic roles:** background, surface, text-primary, text-secondary, accent, destructive.
- **Accessibility:** WCAG AA contrast minimum.

### Components
- Pill-shaped buttons. Card-style inputs.
- Album grid: square artwork, title below, lazy-loaded with placeholder.
- Now playing bar: floating bottom, artwork thumb + track + play/pause. Shows buffering indicator when loading.
- Now playing screen: slide up, pull-down dismiss, large artwork, controls below.
- Error banner: non-blocking toast at top of screen. Short message, auto-dismiss or tap-dismiss.

### Motion
- Physical: slides, fades, springs. No jarring cuts.
- Minimal during listening. Music is the experience.
- Loading: tasteful, not a generic spinner.

---

## Rules for AI Coding Sessions

1. **Read this README first.** Every session. It's the source of truth.
2. **One module per session.** Even when two modules are in the same phase, build them in separate sessions with separate files.
3. **Protocol first, implementation second.** Get approval on the interface before building.
4. **Files under 300 lines.** Split by responsibility.
5. **No singletons. No god objects.** Dependency injection only.
6. **Respect domain boundaries.** Library never imports Music. Music never imports Library. Only AppRouter and shared types cross.
7. **Don't optimize prematurely.** Basic flow first.
8. **When in doubt, stop and ask.**
9. **Tests required.** AI writes unit tests. User does device QA.
10. **Each phase gets a branch.** `phase-N-description`. Merge after QA.
11. **Don't touch future phases.**
12. **Shared types are sacred.** Propose changes, don't just make them.
13. **Errors are never swallowed.** No `try?` with silent nil. Every failure surfaces to the user or is explicitly documented as intentionally ignored with a comment explaining why.
14. **Handle every PlaybackState in UI.** Every view that shows playback state must handle `idle`, `buffering`, `playing`, `paused`, and `error`. No state can be left unconsidered.
15. **Main must always be buildable.** Ensure you check that main is up to date and create a new branch per phase.

---

## Backlog (Ideas, Not Commitments)

- Dope loading indicators (AI generates options, pick via feature flags)
- Contextual tab bar accent colors
- Genre pill components (shared album + artist detail)
- Playlist support alongside collections
- Loudness leveling + smart crossfade
- Star rating edits (write back to Plex)

---

## Explicit Non-Goals

- General Plex client parity
- Multi-server support
- Podcast / audiobook support
- Social features
- Desktop client
- Playlist editing
- New music recommendation

---

## Debug Setup

1. Copy `Lunara/LocalConfig.sample.plist` → `Lunara/LocalConfig.plist`.
2. Add to app target (Debug only).
3. Fill in your Plex server URL and auth token for quick sign-in.
4. Fill in `LASTFM_API_KEY` and `LASTFM_API_SECRET` (shared secret) from your [Last.fm API account](https://www.last.fm/api/accounts).
5. Launch Debug → "Quick Sign-In" button.
