# Queue Manager v1

## Goal
Introduce a dedicated queue system that supports Play Now/Next/Later for albums and tracks, persists queue state across app restarts, and adds queue management controls (clear + remove) without introducing a feature flag.

## Requirements
- Ship as the default path (no feature flag).
- Queue ownership lives in a dedicated `QueueManager` component (not embedded in `PlaybackEngine`).
- Queue supports:
  - Album insertion with `Play Now`, `Play Next`, `Play Later`.
  - Track insertion with `Play Now`, `Play Next`, `Play Later` from non-Up-Next track lists.
- Insertion semantics:
  - `Play Now`: replace queue and start immediately from item 1.
  - `Play Next`: insert immediately after currently playing track.
  - `Play Later`: append to queue tail.
  - If queue is empty, `Play Next`/`Play Later` behave like `Play Now`.
- Duplicate tracks are allowed.
- Guard against accidental duplicate inserts:
  - Ignore identical queue insert commands submitted within a 1-second window.
  - Show banner copy: `Queue cue: we heard you already.`
- Partial inserts are allowed:
  - Add playable tracks.
  - Skip unplayable tracks.
  - Show detailed skip reason summary in banner (example: `Queued 8 tracks, skipped 2 (1 missing media source, 1 failed URL build).`).
- Queue persistence includes:
  - Queue entries
  - Current queue position
  - Elapsed playback position
  - Last play/pause state
- Relaunch behavior:
  - Restore queue and now-playing metadata immediately.
  - App restores in paused state (no auto-resume).
- Queue management in Now Playing:
  - Add `Clear Queue` near `Up Next`.
  - `Clear Queue` removes upcoming items only (keeps currently playing track).
  - Up Next rows support swipe-to-delete to remove individual upcoming items.
  - No long-press remove in Up Next v1.
- Queue actions placement:
  - Album cards: long-press menu gets `Play Now/Next/Later`.
  - Album detail: add `Play Next` and `Play Later` actions alongside existing Play action.
  - Track rows (except Now Playing Up Next): long-press/context action menu gets `Play Now/Next/Later`.
- Editing scope:
  - Include clear + remove.
  - Do not implement reorder yet.
  - Architecture must keep reorder straightforward to add later.

## Acceptance Criteria
- Album and track queue actions produce correct insertion behavior for `Play Now/Next/Later`.
- `Play Now` replaces queue and starts immediate playback.
- `Play Next` inserts directly after current playing item.
- `Play Later` appends.
- If queue is empty, `Play Next` and `Play Later` start playback as `Play Now`.
- Queue state survives app restart with current item/time visible in UI.
- Restored session is paused on relaunch.
- `Clear Queue` removes only upcoming items and leaves current playback item intact.
- Swipe-to-delete removes selected upcoming item from queue.
- Duplicate insert protection blocks identical rapid repeat action within 1 second and shows the configured banner copy.
- Partial queue inserts succeed for playable items and surface skipped-item reasons in banner.
- Failure cases surface polished technical error banners (no generic fallback copy).

## Constraints
- Follow existing SwiftUI + MVVM + protocol-first architecture patterns.
- No third-party dependencies.
- Keep `PlaybackEngine` focused on transport/state emission and move queue orchestration logic to `QueueManager`.
- Maintain test-first workflow with full unit coverage for new queue logic.

## Repository Context
- Relevant files:
  - `Lunara/Playback/PlaybackEngine.swift`
  - `Lunara/Playback/PlaybackProtocols.swift`
  - `Lunara/UI/PlaybackViewModel.swift`
  - `Lunara/ContentView.swift`
  - `Lunara/UI/Views/NowPlayingSheetView.swift`
  - `Lunara/UI/Views/AlbumGridView.swift`
  - `Lunara/UI/Views/AlbumDetailView.swift`
  - `Lunara/UI/AlbumDetailViewModel.swift`
  - `Lunara/UI/Views/CollectionDetailView.swift`
  - `Lunara/UI/Views/ArtistDetailView.swift`
  - `Lunara/LibrarySnapshot/LibrarySnapshotStore.swift`
- Existing patterns:
  - Playback currently rebuilds in-memory queue by calling `play(tracks:startIndex:)`.
  - Up Next currently derives from in-memory context track array.
  - Long-press/context menus already exist for download actions on album surfaces.
  - File-backed JSON stores in Application Support are established (`LibrarySnapshotStore`, offline manifest stores).

## Proposed Approach
1. Add a dedicated queue domain
- Create queue models with stable entry IDs so duplicates are allowed and future reorder is simple:
  - `QueueEntry` (id, track metadata/source info, album/context metadata)
  - `QueueState` (entries, currentEntryID/currentIndex, elapsedSeconds, isPlaying)
- Add command model:
  - `QueueInsertMode` (`playNow`, `playNext`, `playLater`)
  - `QueueInsertRequest` (mode, entries, sourceSignature, timestamp)
  - `QueueMutationResult` (state, insertedCount, skippedReasons, duplicateBlocked)

2. Implement `QueueManager` as canonical source of truth
- Actor-backed `QueueManager` handles:
  - insert album/track entries
  - clear upcoming
  - remove upcoming entry
  - advance/rewind position updates
  - playback elapsed/isPlaying updates
  - snapshot restore/save
- Duplicate-tap protection:
  - Track last successful insert signature and timestamp.
  - If same signature reappears within 1 second, reject with `duplicateBlocked = true`.

3. Persist queue with robust file-backed storage
- Add `QueueStateStore` using Application Support JSON (`.../Lunara/queue-state.json`) with atomic writes.
- Include UserDefaults mirror fallback (same resilience pattern as `LibrarySnapshotStore`).
- Save on every queue mutation and key playback-state updates (throttled if needed).
- Load at app start and hydrate `PlaybackViewModel` before main UI renders now-playing surfaces.

4. Integrate `PlaybackViewModel` with `QueueManager`
- `PlaybackViewModel` becomes queue orchestration facade for UI intents:
  - `enqueueAlbum(mode:album:albumRatingKeys:)`
  - `enqueueTrack(mode:track:context:)`
  - `clearUpcomingQueue()`
  - `removeUpcomingQueueEntry(id:)`
- On queue mutation:
  - Ask `QueueManager` to mutate.
  - Reconcile player pipeline from queue snapshot.
  - Publish now-playing context + up-next data from queue state (not ad hoc arrays).
- On playback callbacks:
  - Update `QueueManager` current position and elapsed state.

5. Expand player integration for non-destructive upcoming edits
- Keep current track stable while modifying upcoming queue:
  - Build adapter APIs to replace upcoming items without dropping the current item.
  - If backend limitations force a queue rebuild, restore current track + elapsed time and keep paused/playing state consistent.
- Keep this behind `PlaybackEngine` so queue logic remains decoupled from AVFoundation specifics.

6. UI updates
- Now Playing sheet:
  - Add `Clear Queue` action in Up Next header with destructive confirmation.
  - Add swipe-to-delete for upcoming rows only.
- Album/detail/track surfaces:
  - Extend existing menus/actions to include `Play Now/Next/Later`.
  - Exclude Now Playing Up Next list from add-to-queue actions.
- Banner messaging:
  - Duplicate block: `Queue cue: we heard you already.`
  - Partial insert success/failure with reason breakdown.

## Alternatives Considered
1. Keep queue logic inside `PlaybackEngine`
- Pros: less immediate refactor.
- Cons: mixes queue orchestration with transport concerns and makes persistence/testing/UI mutation logic harder.

2. UserDefaults-only persistence
- Pros: simpler implementation.
- Cons: less robust for larger payloads and weaker recovery guarantees vs file-backed JSON + fallback.

3. Full queue editing (including reorder) in v1
- Pros: richer functionality immediately.
- Cons: added scope/risk for Phase 1 completion; defer reorder while preserving reorder-ready architecture.

## Pseudocode
```swift
actor QueueManager {
    private var state: QueueState
    private var lastInsertSignature: String?
    private var lastInsertDate: Date?
    private let store: QueueStateStoring

    func insert(_ request: QueueInsertRequest) async -> QueueMutationResult {
        if isDuplicateBurst(request) {
            return .duplicateBlocked(state)
        }

        let resolved = request.entries.reduce(into: ResolvedInsert()) { result, entry in
            if entry.isPlayable {
                result.playable.append(entry)
            } else {
                result.skipped.append(entry.skipReason)
            }
        }

        guard !resolved.playable.isEmpty else {
            return .failed(state, skipped: resolved.skipped)
        }

        if state.entries.isEmpty || request.mode == .playNow {
            state.entries = resolved.playable
            state.currentIndex = 0
            state.elapsedSeconds = 0
            state.isPlaying = true
        } else if request.mode == .playNext {
            let insertIndex = min(state.currentIndex + 1, state.entries.count)
            state.entries.insert(contentsOf: resolved.playable, at: insertIndex)
        } else { // .playLater
            state.entries.append(contentsOf: resolved.playable)
        }

        stampInsert(request)
        try? store.save(state)
        return .success(state, inserted: resolved.playable.count, skipped: resolved.skipped)
    }

    func clearUpcoming() async {
        guard !state.entries.isEmpty else { return }
        let current = state.entries[state.currentIndex]
        state.entries = [current]
        state.currentIndex = 0
        try? store.save(state)
    }

    func removeUpcoming(entryID: UUID) async {
        guard let idx = state.entries.firstIndex(where: { $0.id == entryID }) else { return }
        guard idx != state.currentIndex else { return } // v1: cannot remove currently playing
        state.entries.remove(at: idx)
        if idx < state.currentIndex { state.currentIndex -= 1 }
        try? store.save(state)
    }

    func updatePlayback(elapsedSeconds: TimeInterval, isPlaying: Bool, currentEntryID: UUID?) async {
        state.elapsedSeconds = elapsedSeconds
        state.isPlaying = isPlaying
        if let currentEntryID, let index = state.entries.firstIndex(where: { $0.id == currentEntryID }) {
            state.currentIndex = index
        }
        try? store.save(state)
    }
}
```

```swift
@MainActor
final class PlaybackViewModel {
    func enqueueAlbum(mode: QueueInsertMode, album: PlexAlbum, tracks: [PlexTrack]) {
        Task {
            let request = QueueInsertRequest.album(mode: mode, album: album, tracks: tracks, now: dateProvider())
            let result = await queueManager.insert(request)
            await applyQueueMutation(result)
        }
    }

    func applyQueueMutation(_ result: QueueMutationResult) async {
        if result.duplicateBlocked {
            errorMessage = "Queue cue: we heard you already."
            return
        }

        if result.insertedCount > 0 {
            engine.syncQueue(result.state.entries, currentIndex: result.state.currentIndex)
            if result.state.isPlaying {
                engine.playCurrentIfNeeded()
            } else {
                engine.pause()
            }
            if result.skippedReasons.isEmpty == false {
                errorMessage = QueueBannerFormatter.partialSuccess(inserted: result.insertedCount, skipped: result.skippedReasons)
            }
        } else {
            errorMessage = QueueBannerFormatter.failure(reasons: result.skippedReasons)
        }
    }
}
```

## Test Strategy
- Unit tests:
  - `QueueManager` insertion semantics for `playNow/playNext/playLater`.
  - Empty-queue behavior where `playNext/playLater` becomes immediate playback.
  - Duplicate-burst suppression within 1 second for identical requests.
  - Duplicates allowed outside suppression window.
  - Partial insert success with accurate skipped-reason aggregation.
  - `clearUpcoming` preserves current item.
  - `removeUpcoming` removes non-current upcoming item and keeps indices coherent.
  - Persistence round-trip restore (entries/index/elapsed/isPlaying).
  - Relaunch restore publishes paused now-playing state and visible bar metadata.
  - Playback callback synchronization updates persisted elapsed and play/pause state.
- Edge cases:
  - Remove last upcoming item.
  - Remove item before current index (index shift correctness).
  - Current track unavailable during restore (fallback to next playable or nil state with banner).
  - Large queue payload save/load reliability.

## Risks / Tradeoffs
- Synchronizing queue mutations with AVQueue playback without disrupting current track requires careful adapter boundaries.
- Frequent persistence writes can be noisy; may need debounce/throttle for elapsed-time updates.
- Detailed skip reason reporting depends on consistent lower-level error mapping from source resolution and media parsing.

## Open Questions
- None. Scope and behaviors are confirmed for v1.
