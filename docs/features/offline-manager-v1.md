# Offline Manager v1 (Phase 1.11)

## Goal
Add reliable, Wi-Fi-only offline audio downloads for albums and collections, with local-first playback, explicit-vs-collection ownership rules, and a dedicated downloads management screen.

## Requirements
- User can start an album download from:
  - Long-press on album cards in all album grids.
  - A `Download Album` control at the bottom of album detail.
- User can start a collection download from long-press in the collections grid.
- Album download uses the deduped album group (`albumRatingKeys`) and should not re-download already complete tracks.
- Collection downloads store collection-to-album membership and auto-reconcile on every collections refresh.
- If album membership is removed from a downloaded collection:
  - Keep album downloaded if it was explicitly downloaded outside collection.
  - Otherwise remove album from local downloads.
- Downloads are Wi-Fi only for v1 (manual and opportunistic).
- Opportunistic caching should attempt current/next tracks context and queue the next 5 tracks (when on Wi-Fi).
- Manage Downloads is a dedicated screen pushed from Settings.
- Manage Downloads sections:
  - In Progress
  - Downloaded Albums
  - Downloaded Collections
  - Stream-Cached
- Manage Downloads supports swipe actions:
  - In Progress: cancel
  - Downloaded Albums: remove download
  - Downloaded Collections: remove collection download (with reconciliation)
- Downloaded files must be complete and verified before marking offline-ready.
- If file download fails or verification fails, remove partial file and mark track incomplete.
- Playback checks local offline index first.
- If offline and no local tracks are available for a request, playback emits user-facing error banner.
- Auto-resume queued/pending downloads when Wi-Fi becomes available while app is open.
- Add 120 GB offline cap with eviction:
  - Evict non-explicit downloads first.
  - Eviction policy: LRU by last played.
  - If only explicit downloads remain and still over limit, block new downloads and surface storage error.
- Sign out behavior:
  - If completed offline file count is 0, keep existing sign-out flow.
  - If completed offline file count > 0, present a second confirmation:
    - `Signing out will remove X files, are you sure?`
  - Confirming second prompt removes offline files/metadata, then signs out.

## Acceptance Criteria
- Album/collection download entry points exist in required surfaces and start Wi-Fi-only download workflow.
- Download status is visible and updates live in Manage Downloads with per-track and aggregate progress.
- Collection membership is reconciled on each collections refresh and respects explicit-download precedence.
- Playback uses local file when available and skips missing local tracks immediately while offline.
- Stream caching and next-5 opportunistic caching only run on Wi-Fi.
- Offline storage cap is enforced at 120 GB with non-explicit LRU eviction.
- Sign-out second confirmation appears only when completed file count is non-zero and clears offline artifacts on confirm.

## Constraints
- No third-party dependencies.
- Foreground-only download reliability for v1.
- Preserve existing SwiftUI + MVVM + protocol-injection patterns.
- Keep `main` healthy with PR-sized increments and explicit approval checkpoints.

## Repository Context
- Relevant files:
  - `Lunara/Playback/PlaybackSource.swift`
  - `Lunara/UI/PlaybackViewModel.swift`
  - `Lunara/Playback/PlaybackEngine.swift`
  - `Lunara/UI/Views/AlbumGridView.swift`
  - `Lunara/UI/Views/AlbumDetailView.swift`
  - `Lunara/UI/Views/CollectionsBrowseView.swift`
  - `Lunara/UI/Views/CollectionDetailView.swift`
  - `Lunara/UI/Views/ArtistDetailView.swift`
  - `Lunara/UI/Views/SettingsView.swift`
  - `Lunara/UI/SettingsViewModel.swift`
  - `Lunara/Plex/AppSettingsStore.swift`
  - `Lunara/Plex/PlexProtocols.swift`
  - `Lunara/Plex/Library/PlexLibraryService.swift`
  - `Lunara/Artwork/ArtworkDiskCache.swift`
  - `Lunara/LibrarySnapshot/LibrarySnapshotStore.swift`
- Existing patterns:
  - Protocol-first services and stores.
  - Lightweight disk index persistence via JSON.
  - Root-level settings sheet and shared `SettingsViewModel`.
  - Playback source abstraction already supports `.local(fileURL)` and `.remote(url)`.

## Options Considered
### Option A: Actor-backed offline domain + JSON manifest + file-system storage (Recommended)
- Build an `OfflineDownloadsCoordinator` actor with explicit models for tracks/albums/collections and a single download queue.
- Persist manifest/index in Application Support; store files in `Application Support/OfflineAudio/`.
- Integrate via existing protocols (`LocalPlaybackIndexing`, settings/store patterns).
- Pros:
  - Aligns with current architecture.
  - Easy deterministic unit testing.
  - Minimal schema tooling overhead for v1.
- Cons:
  - Manual migration/versioning of manifest.

### Option B: Introduce SQLite/Core Data offline schema now
- Pros:
  - Better long-term query flexibility.
- Cons:
  - Higher upfront complexity and migration burden for v1 timeline.

### Option C: Download-only layer with no ownership model
- Pros:
  - Fastest initial implementation.
- Cons:
  - Fails explicit-vs-collection ownership and reconciliation requirements.

## Decision
Adopt Option A for phase 1.11.

## Proposed Approach
### 1. Offline domain models and storage
- Add offline persistence models:
  - `OfflineTrackRecord`: `trackRatingKey`, `partKey`, `relativeFilePath`, `expectedBytes`, `actualBytes`, `state`, `isOpportunistic`, `lastPlayedAt`, `completedAt`.
  - `OfflineAlbumRecord`: `albumIdentity`, `displayTitle`, `trackKeys`, `isExplicit`, `collectionKeys`.
  - `OfflineCollectionRecord`: `collectionKey`, `title`, `albumIdentities`, `lastReconciledAt`.
  - `OfflineManifest`: top-level document with model version and indexes.
- Persist manifest JSON atomically (pattern mirrors artwork/snapshot stores).
- Store completed audio files under `Application Support/OfflineAudio/tracks/<track-or-part-hash>.audio`.

### 2. Download orchestration (Wi-Fi only, foreground only)
- Add `OfflineDownloadsCoordinator` actor:
  - Enqueue album download (deduped album group track list).
  - Enqueue collection download (album set + membership writes).
  - Enqueue opportunistic next-5 track downloads.
  - Track per-track progress + aggregate progress by album/collection.
  - Verify completion before commit:
    - `URLSessionDownloadTask` completes.
    - File exists and size > 0.
    - If `expectedContentLength` is known, require byte match.
    - Move from temp to final destination atomically.
  - On failure, remove temp/final partials and clear incomplete state.
- Add `WiFiReachabilityMonitor` wrapper (`NWPathMonitor`):
  - If not on Wi-Fi, queue remains pending.
  - On Wi-Fi regain while app is open, resume pending work automatically.

### 3. Ownership rules (explicit vs collection)
- Download source flags:
  - Explicit album download sets `isExplicit = true`.
  - Collection download adds `collectionKey` membership for each album.
- Reconciliation on each collections refresh:
  - For every downloaded collection, fetch live album set.
  - Add new albums to download queue if missing.
  - Remove stale album membership.
  - If album has no remaining collection membership and `isExplicit == false`, remove album + tracks.

### 4. Playback integration
- Implement `OfflinePlaybackIndex: LocalPlaybackIndexing` backed by offline manifest.
- Wire `PlaybackViewModel.defaultEngineFactory` to inject `OfflinePlaybackIndex` into `PlaybackSourceResolver`.
- Offline behavior:
  - If local exists -> play local.
  - If no local and network available -> play remote.
  - If no local and offline -> skip immediately.
  - If request yields no playable tracks, emit playback error banner message.
- Track `lastPlayedAt` updates for local playback to drive LRU eviction.

### 5. Opportunistic caching (current + next 5, Wi-Fi only)
- Add hooks from playback state updates:
  - On state change, enqueue current + next 5 tracks from active context.
  - Skip tracks already complete/in-progress.
  - Only enqueue on Wi-Fi.
- Keep source-agnostic input path so queue/shuffle can reuse same API later.

### 6. Storage cap and eviction (120 GB)
- Pre-download admission:
  - If projected size exceeds cap, run eviction first.
- Eviction strategy:
  - Candidate set = non-explicit tracks only.
  - Order by `lastPlayedAt` ascending (oldest first; nil oldest).
  - Remove until under cap.
- If still over cap and only explicit downloads remain, reject new download with storage error.

### 7. UI integration
- Album long-press (`AlbumGridView`, collection/artist album rows):
  - Context menu action: `Download Album`.
- Collection long-press (`CollectionsBrowseView`):
  - Context menu action: `Download Collection`.
- Album detail bottom control (`AlbumDetailView`):
  - Add section below details with stateful button:
    - `Download Album`
    - `Downloading…`
    - `Downloaded`
    - `Remove Download`
- Settings:
  - Add `Manage Downloads` navigation entry in `SettingsView`.
  - New `ManageDownloadsView` + `ManageDownloadsViewModel`.
  - Show required sections and progress indicators.
  - Add swipe actions per section requirements.

### 8. Sign-out second confirmation + offline purge
- Extend `SettingsViewModel` sign-out flow:
  - First confirmation remains unchanged.
  - After first confirm, fetch completed offline file count.
  - If count == 0: sign out immediately.
  - If count > 0: show second confirmation with exact count.
- On second confirm:
  - Purge offline files and manifest.
  - Then call existing sign-out action.

## Implementation Slices (PR-sized)
1. Core offline domain
- Add manifest models, disk store, file pathing, and tests.
2. Download coordinator + Wi-Fi monitor
- Add queueing/progress/verification and tests.
3. Playback integration
- Wire `OfflinePlaybackIndex`, offline skip behavior, and tests.
4. Album/collection download entry points
- Add long-press + album-detail button states and tests.
5. Manage Downloads screen
- Add dedicated view, sections, swipe actions, and tests.
6. Collections reconciliation + eviction
- Add reconcile-on-refresh and 120 GB LRU eviction tests.
7. Sign-out second confirmation and purge
- Add two-step confirmation behavior and tests.

Each slice should stop for approval before continuing.

## Pseudocode
```swift
actor OfflineDownloadsCoordinator {
    func enqueueAlbumDownload(album: PlexAlbum, albumRatingKeys: [String], source: DownloadSource) async throws {
        guard wifiMonitor.isOnWiFi else { throw OfflineError.wifiRequired }
        let tracks = try await trackFetcher.fetchMergedTracks(albumRatingKeys)
        let albumIdentity = albumIdentityBuilder.identity(for: album)
        manifest.upsertAlbum(albumIdentity, explicit: source == .explicitAlbum)
        try await enqueueTracks(tracks, albumIdentity: albumIdentity, source: source)
    }

    func enqueueCollectionDownload(collection: PlexCollection, sectionKey: String) async throws {
        guard wifiMonitor.isOnWiFi else { throw OfflineError.wifiRequired }
        let albums = try await library.fetchAlbumsInCollection(sectionKey, collection.ratingKey)
        manifest.upsertCollection(collectionKey: collection.ratingKey, albums: albums)
        for album in albums {
            try await enqueueAlbumDownload(album: album, albumRatingKeys: [album.ratingKey], source: .collection(collection.ratingKey))
        }
    }

    func enqueueOpportunistic(current: PlexTrack, upcoming: [PlexTrack], limit: Int = 5) async {
        guard wifiMonitor.isOnWiFi else { return }
        let tracks = Array(([current] + upcoming).prefix(limit + 1))
        await enqueueIfNeeded(tracks, source: .opportunistic)
    }

    func reconcileDownloadedCollections(sectionKey: String) async throws {
        for collection in manifest.downloadedCollections {
            let liveAlbums = try await library.fetchAlbumsInCollection(sectionKey, collection.key)
            let diff = membershipDiff(stored: collection.albumIdentities, live: liveAlbums)
            try await applyCollectionMembershipDiff(diff, collectionKey: collection.key)
        }
    }

    func enforceStorageCap(maxBytes: Int = 120 * 1024 * 1024 * 1024) async throws {
        if manifest.totalBytes <= maxBytes { return }
        let evictable = manifest.nonExplicitTracksSortedByLastPlayedAscending()
        for track in evictable where manifest.totalBytes > maxBytes {
            try removeTrack(track.key)
        }
        if manifest.totalBytes > maxBytes {
            throw OfflineError.insufficientStorageNonEvictable
        }
    }
}

struct OfflinePlaybackIndex: LocalPlaybackIndexing {
    func fileURL(for trackKey: String) -> URL? {
        guard let track = manifest.completedTrack(for: trackKey) else { return nil }
        return fileStore.absoluteURL(for: track.relativeFilePath)
    }
}

// Playback source resolution
func resolveSource(for track: PlexTrack) -> PlaybackSource? {
    if let local = offlineIndex.fileURL(for: track.ratingKey) {
        return .local(fileURL: local)
    }
    if networkMonitor.isReachable {
        return .remote(url: urlBuilder.makeDirectPlayURL(partKey: track.partKey))
    }
    return nil // offline and not downloaded -> skip
}

// Settings sign out flow
func confirmSignOutStepOne() async {
    let count = await offlineCoordinator.completedFileCount()
    if count == 0 {
        onSignOut()
    } else {
        presentSecondConfirmation(message: "Signing out will remove \(count) files, are you sure?")
    }
}

func confirmSignOutStepTwo() async {
    try await offlineCoordinator.purgeAll()
    onSignOut()
}
```

## Test Strategy
- Unit tests:
  - Manifest store load/save/version fallback.
  - Track completion verification commits only complete files.
  - Failed/cancelled download removes partials and leaves no complete record.
  - Wi-Fi gating prevents enqueue and resumes pending work when Wi-Fi returns.
  - Album explicit ownership vs collection ownership transitions.
  - Collection reconciliation diffing (add/remove albums) on refresh.
  - Offline playback source resolution (local preferred, remote fallback, offline skip).
  - Opportunistic next-5 enqueue honors Wi-Fi-only and dedupe checks.
  - 120 GB cap eviction only targets non-explicit tracks by `lastPlayedAt` LRU.
  - Storage error when only explicit tracks remain and cap still exceeded.
  - Settings two-step sign-out confirmation and zero-file skip path.
  - Offline purge clears files + metadata before sign-out callback.
- UI/view-model tests:
  - Long-press actions appear on album and collection cards.
  - Album detail bottom button state transitions.
  - Manage Downloads section rendering and progress labels.
  - Swipe action handlers per section.
  - Playback error banner shown when no offline-playable tracks are available offline.
- Edge cases:
  - Duplicate album groups with overlapping track sets.
  - Missing/invalid part keys.
  - App relaunch during in-progress queue (recover pending state).
  - Collections refresh while download queue active.

## Risks / Tradeoffs
- `AVPlayer` stream buffers are not reliable as offline artifacts; explicit downloader is required for correctness.
- Reconciliation on every collections refresh can be network-heavy; acceptable for v1 correctness, optimize later.
- JSON manifest is fast to ship but needs careful schema versioning discipline.
- Foreground-only behavior may surprise users expecting background completion; messaging should be explicit in UI.

## Open Questions
- None for phase 1.11 scope.
