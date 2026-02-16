# Playback Rewrite Phased Cutover Plan

## Goal
Rewrite the audio playback architecture end-to-end in small, approval-gated phases with manual device validation after each phase.

## Constraints (User Confirmed)
- Full rewrite is preferred over preserving current internals.
- New Git branch per phase (`codex/...`).
- Pause after every phase for user approval before continuing.
- Manual testing is device-only (iPhone 15 Pro, iOS 26.2).
- No legacy fallback mode is required.
- Agent runs unit tests; user focus is manual verification.
- Local diagnostics file is required.
- Gapless/crossfade is first fast follow after rewrite foundation.

## Architecture Findings That Drive This Rewrite
- Playback state is split across multiple owners (engine, queue store, and view-model context), creating desync risk.
- Relaunch priming behavior can produce play/pause inconsistencies.
- Detail screens re-fetch data on re-entry, causing perceived reload churn.
- Browse view models load snapshot and still always refresh from Plex, conflicting with manual-refresh intent.
- Offline source lookups repeatedly decode manifest data on hot paths.
- Downloader currently buffers full payloads in memory.

## Phase 0 - Diagnostics Baseline
### Branch
- `codex/rewrite-p0-diagnostics-baseline`

### Scope
- Add diagnostics logger with JSONL output in app support.
- Add session IDs and playback session IDs.
- Instrument startup/play/skip/UI sync/library navigation events.

### Exit Criteria
- Diagnostics file is created and populated for core playback/navigation actions.
- Baseline metrics can be computed:
  - startup-to-first-audio
  - skip-to-audio
  - skip-to-ui-sync

### Manual Test Script
1. Force-quit app.
2. Launch app and play a cached track.
3. Press Next 5 times.
4. Navigate Collections -> Collection -> Album -> Back.
5. Confirm diagnostics entries exist for each action path.

### Notes
- `state_change` and `ui_sync` events are chatty (~1/sec from the engine's periodic time ticker). A 60-second session produces 200+ lines, mostly periodic noise. When computing skip-to-audio and skip-to-ui-sync latency in P1+, filter on the signal events (`playback.play`, `playback.skip_next`, `playback.audio_started`) and ignore the periodic updates.

### Approval Checkpoint
- "Approve P0 baseline."

## Phase 1 - Playback Domain Rewrite (Single Source of Truth)
### Branch
- `codex/rewrite-p1-playback-domain`

### Scope
- Introduce a single concurrency-owned playback domain (actor).
- Move queue progression, current item, and playback state ownership into the domain.
- Convert UI to consume one immutable read model stream.

### Exit Criteria
- Audible track and now-playing UI stay synchronized under repeated next/previous actions.
- Queue index and displayed metadata remain consistent in Now Playing and Up Next.

### Manual Test Script
1. Build a mixed queue with tracks from multiple albums.
2. Tap Next/Previous rapidly 20 times.
3. Verify title/artist/artwork always matches audible track.
4. Open Now Playing and verify Up Next order matches real progression.

### Approval Checkpoint
- "Approve P1 state unification."

## Phase 2 - Durable Queue and Relaunch Semantics
### Branch
- `codex/rewrite-p2-durable-queue`

### Scope
- Add durable playback session persistence owned by the new domain.
- Restore queue and elapsed position on launch while waiting for explicit Play.
- If restored item is unavailable locally, skip to next playable item.

### Exit Criteria
- Force-quit/relaunch consistently restores queue and position.
- Playback starts only on explicit user action.

### Manual Test Script
1. Start playback, pause mid-track, note timestamp.
2. Force-quit app and relaunch.
3. Verify queue and current track are restored but not auto-playing.
4. Press Play and verify resume behavior (or skip to next available if missing).

### Approval Checkpoint
- "Approve P2 durability."

## Phase 3 - Offline Download Engine Rewrite
### Branch
- `codex/rewrite-p3-download-engine`

### Scope
- Replace full-buffer downloads with stream-oriented file writes.
- Rework offline index access for constant-time hot-path lookup.
- Add predictive prefetch of next 3 tracks.
- Enforce 128 GB cap with dynamic eviction policy.

### Exit Criteria
- Downloads complete reliably with accurate progress.
- Playback source resolution is local-first and low-latency.
- Predictive prefetch is active for next 3 tracks.

### Manual Test Script
1. Download an album and a collection.
2. Play downloaded tracks and skip through queue.
3. Confirm next-3 prefetch activity in diagnostics.
4. Fill storage near cap and verify eviction behavior is coherent.

### Approval Checkpoint
- "Approve P3 offline engine."

## Phase 4 - Library Repository Rewrite (Disk-First, Manual Refresh)
### Branch
- `codex/rewrite-p4-library-repository`

### Scope
- Introduce disk-first repository for collections/albums/artists/details.
- Use cached data on navigation backstack reuse.
- Network refresh only on explicit pull-to-refresh.

### Exit Criteria
- Back navigation no longer triggers full-page reload behavior.
- Manual refresh remains available and uses Plex as source of truth.

### Manual Test Script
1. Open Collections.
2. Enter Collection -> Album -> Back.
3. Verify collection screen returns instantly without full reload spinner.
4. Pull-to-refresh and verify fresh data path executes.

### Approval Checkpoint
- "Approve P4 repository behavior."

## Phase 5 - Background and Remote Control Hardening
### Branch
- `codex/rewrite-p5-background-remote`

### Scope
- Harden background lifecycle handling in playback domain.
- Ensure lock-screen/Control Center metadata updates are consistent and ordered.
- Harden remote command handling for play/pause/next/previous.

### Exit Criteria
- Remote commands are reliable through lock/unlock/background transitions.
- Metadata remains accurate during rapid command usage.

### Manual Test Script
1. Start playback and lock device.
2. Use remote controls repeatedly (play/pause/next/previous).
3. Lock/unlock repeatedly and verify state continuity.
4. Confirm metadata remains correct throughout.

### Approval Checkpoint
- "Approve P5 remote stability."

## Phase 6 - Performance and Regression Sweep
### Branch
- `codex/rewrite-p6-performance-polish`

### Context
Shuffling a large collection ("Key Albums", thousands of tracks) freezes the UI for 22+ seconds. Four compounding bottlenecks cause this:
1. Sequential network fetches for every album in the collection (`CollectionAlbumsViewModel.swift:145-153` — `for album in albums { service.fetchTracks(...) }`).
2. Entire queue built and shuffled on the main thread before playback starts (`CollectionAlbumsViewModel.swift:160`).
3. Synchronous JSON serialization of the full queue to disk on every state mutation (`QueueManager.swift:360-365` — `persist()` calls `store.save(state)` inline).
4. Non-virtualized `ForEach` rendering all 3000+ `UpNextRow` views at once (`NowPlayingSheetView.swift:192-200`).

Additionally, P1's `PlaybackDomain` actor (commit `8790d4f`) lives on an unmerged branch. Current P5 HEAD still uses split ownership across `PlaybackEngine`/`QueueManager`/`PlaybackViewModel`. A consolidation report is a document deliverable of this phase.

### Sub-Phases

Each sub-phase is one PR with unit tests. P6.1 and P6.2 can ship in parallel. P6.4 must land before P6.3.

#### P6.1 — Lazy Up Next Rendering
**Problem:** `NowPlayingSheetView.swift:192` uses a plain `ForEach` inside a `VStack`. SwiftUI instantiates all 3000+ `UpNextRow` views immediately, causing scroll freeze.

**Implementation:**
- Wrap the Up Next `ForEach` in a `LazyVStack` inside `upNextSection`.
- Add a `limit` parameter to `NowPlayingUpNextBuilder.upNextItems(tracks:currentIndex:limit:)` — default 50.
- When the full queue exceeds the limit, append a footer row: `"N more tracks in queue"`.

**Files to modify:**
- `Lunara/UI/Views/NowPlayingSheetView.swift` — replace `VStack` containing the `ForEach` with `LazyVStack`, pass `limit: 50` to `upNextItems()`, add footer.
- `Lunara/UI/Views/NowPlayingHelpers.swift` — add `limit` parameter to `upNextItems()`, slice the result.

**Unit tests:**
- `upNextItems(tracks: 5000Items, currentIndex: 0, limit: 50)` returns exactly 50 items.
- `upNextItems(tracks: 10Items, currentIndex: 0, limit: 50)` returns all 10 items.
- Footer text correctly computes remaining count.

---

#### P6.2 — Background Queue Persistence
**Problem:** `QueueManager.persist()` (line 360) synchronously encodes the entire `QueueState` (thousands of `QueueEntry` objects with full track/album metadata) to JSON and writes to disk. This blocks the main thread on every `setState`, `insert`, or `remove` call.

**Implementation:**
- Add a private `DispatchQueue` (label: `com.lunara.queue-persist`, qos: `.utility`).
- Add a `DispatchWorkItem?` for debounce tracking.
- Replace the body of `persist()`:
  1. Cancel any pending debounce work item.
  2. Capture `self.state` (value type snapshot).
  3. Schedule a new work item on the background queue after 300ms.
  4. In the work item: encode and write via `store.save(capturedState)`.
- Add `persistImmediately()` (no debounce) for use during app termination — call from `scenePhaseChange(.background)` in `PlaybackViewModel`.
- Keep all in-memory `state` mutations synchronous on `@MainActor`.

**Files to modify:**
- `Lunara/Playback/QueueManager.swift` — rewrite `persist()`, add `persistImmediately()`, add background queue and debounce work item.
- `Lunara/UI/PlaybackViewModel.swift` — call `queueManager.persistImmediately()` on background scene phase.

**Unit tests (use `MockQueueStateStore` to count save calls):**
- 5 rapid `setState` calls within 300ms → exactly 1 `store.save()` call after debounce.
- `persistImmediately()` triggers `store.save()` synchronously (no debounce).
- In-memory `snapshot()` returns correct state immediately after `setState`, before persist fires.

---

#### P6.3 — Fast Shuffle Start (Two-Phase Queue)
**Problem:** `CollectionAlbumsViewModel.playCollection(shuffled: true)` fetches tracks for ALL albums before starting playback. With hundreds of albums this takes 10+ seconds of sequential network calls before any audio plays.

**Depends on:** P6.4 (parallel fetching).

**Implementation — two-phase approach:**

**Phase 1 — Immediate playback (target <2s to first audio):**
1. Shuffle the already-loaded `albums` array in memory (O(n), fast).
2. Take the first 5 shuffled albums.
3. Fetch their tracks in parallel using `withThrowingTaskGroup` (from P6.4).
4. Shuffle the resulting tracks, call `playbackController.play(tracks:startIndex:context:)`.
5. Audio starts, UI is responsive. Mark `isPreparingPlayback = false`.

**Phase 2 — Background fill:**
6. Spawn a detached `Task` that continues fetching remaining albums in batches of 10, using `withThrowingTaskGroup` with concurrency limit.
7. As each batch completes, shuffle the new tracks and call `playbackController.enqueue(.playLater, tracks:context:)`.
8. Maintain `seenTrackKeys` across both phases for deduplication.
9. Store the background `Task` handle. Cancel it if the user starts new playback (check in `playCollection` guard or `play()` on `PlaybackViewModel`).

**Files to modify:**
- `Lunara/UI/CollectionAlbumsViewModel.swift` — rewrite `playCollection(shuffled:)` with two-phase logic. Add `private var backgroundFillTask: Task<Void, Never>?` property. Cancel in `deinit` and at top of `playCollection`.
- `Lunara/UI/PlaybackViewModel.swift` — verify `enqueue(.playLater, ...)` path works for appending tracks to an active queue without restarting playback. If `insertIntoQueue` restarts playback, fix it to append-only.

**Unit tests (use `MockPlaybackController` and `MockLibraryService`):**
- Phase 1 calls `play()` with only the first batch of tracks (≤5 albums worth).
- Phase 2 calls `enqueue(.playLater, ...)` with remaining tracks.
- `seenTrackKeys` prevents duplicates across phases.
- Starting new playback cancels background fill task.
- Error in phase 2 does not crash or affect phase 1 playback.

---

#### P6.4 — Parallel Track Fetching
**Problem:** The `for album in albums` loop at `CollectionAlbumsViewModel.swift:145-153` fetches tracks sequentially. With 100 albums, that's 100+ serial network calls.

**Implementation:**
- Extract a reusable async method:
  ```swift
  private func fetchTracksForAlbums(
      _ albums: [PlexAlbum],
      using service: PlexLibraryServicing
  ) async throws -> [PlexTrack]
  ```
- Use `withThrowingTaskGroup(of: (String, [PlexTrack]).self)` to fetch all albums in parallel.
- Each child task: `let tracks = try await service.fetchTracks(albumRatingKey: key)` → return `(key, sortTracks(tracks))`.
- Collect results, deduplicate via `seenTrackKeys`.
- Replace the sequential loop in `playCollection` with a call to this method.

**Files to modify:**
- `Lunara/UI/CollectionAlbumsViewModel.swift` — extract parallel fetch method, replace sequential loop.

**Unit tests:**
- Mock service with artificial delay — verify all albums fetch concurrently (total time ≈ 1 album's delay, not N × delay).
- Deduplication still works with parallel results arriving in arbitrary order.

---

#### P6.5 — Latency Instrumentation
**Problem:** Existing diagnostics log discrete events but no timing data. Cannot measure shuffle-to-audio or skip-to-audio latency from the JSONL file.

**Implementation:**

**New diagnostic events** (add to `DiagnosticsEvent.swift`):
- `shuffleStarted(albumCount: Int)` — logged when shuffle begins.
- `shufflePhase1Complete(trackCount: Int, durationMs: Int)` — logged when phase 1 playback starts.
- `shufflePhase2Complete(trackCount: Int, durationMs: Int)` — logged when background fill finishes.
- `playbackLatency(operation: String, durationMs: Int)` — generic latency event for:
  - `operation: "play_to_audio"` — time from `play()` call to `handleItemChanged` firing.
  - `operation: "skip_to_audio"` — time from `skipToNext/Previous()` to next `handleItemChanged`.

**Timing context on PlaybackEngine:**
- Add `private var operationStartTimes: [String: Date] = [:]` dictionary.
- In `play()`: store `operationStartTimes["play_to_audio"] = Date()`.
- In `skipToNext()`/`skipToPrevious()`: store `operationStartTimes["skip_to_audio"] = Date()`.
- In `handleItemChanged()` (the callback that fires when AVPlayer advances): compute delta from stored start time, log `playbackLatency(operation:durationMs:)`, clear the entry.

**Shuffle timing on CollectionAlbumsViewModel:**
- At top of `playCollection(shuffled: true)`: `let shuffleStart = Date()`, log `shuffleStarted(albumCount:)`.
- After phase 1 `play()` call: log `shufflePhase1Complete(trackCount:durationMs:)`.
- After phase 2 completes: log `shufflePhase2Complete(trackCount:durationMs:)`.

**Files to modify:**
- `Lunara/Diagnostics/DiagnosticsEvent.swift` — add new event cases and their `name`/`data` encoding.
- `Lunara/Playback/PlaybackEngine.swift` — add `operationStartTimes`, instrument `play()`, `skipToNext()`, `skipToPrevious()`, `handleItemChanged()`.
- `Lunara/UI/CollectionAlbumsViewModel.swift` — instrument shuffle phases.

**Unit tests:**
- `playbackLatency` event `durationMs` is positive when mocked with known delay.
- `operationStartTimes` clears the entry after logging (no stale timings).
- Shuffle events include correct `albumCount` and `trackCount`.

---

#### P6.6 — Baseline Comparison Workflow
**Purpose:** Enable the user to capture P0 and P6 diagnostics and compare latency metrics.

**Baseline capture instructions (include in `docs/diagnostics-baseline-workflow.md`):**
1. Build the P0 baseline: checkout `e15e687`, build and run on device.
2. Perform test scenario: force-quit → launch → shuffle "Key Albums" → skip 5 times → play an album → navigate Collections → Album → Back.
3. Go to Settings → "Share Diagnostics Log" → AirDrop/save the file → rename to `diagnostics-p0.jsonl`.
4. Build the P6 branch, repeat exact same test scenario.
5. Export → rename to `diagnostics-p6.jsonl`.
6. Run: `python3 scripts/compare_diagnostics.py diagnostics-p0.jsonl diagnostics-p6.jsonl`.

**Note:** P0 baseline will NOT have the new latency events from P6.5 (those didn't exist yet). The script should compute latency from event timestamp deltas for P0 (e.g., `playback.play` timestamp → `playback.audio_started` timestamp) and from explicit `durationMs` fields for P6.

**Deliverable:** `scripts/compare_diagnostics.py`
- Parses JSONL, groups events by `playbackSessionId`.
- For P0 files (no `durationMs`): compute latency from timestamp deltas between `playback.play` → `playback.audio_started`, and `playback.skip_next` → `playback.audio_started`.
- For P6 files: use `playbackLatency` event `durationMs` directly.
- Prints side-by-side table: operation | P0 avg ms | P6 avg ms | delta.

**Files to create:**
- `scripts/compare_diagnostics.py`
- `docs/diagnostics-baseline-workflow.md`

**Unit tests (for the Python script):**
- Parses sample JSONL with known events, computes correct latency.
- Handles missing fields gracefully (P0 format vs P6 format).

---

#### P6.7 — Code Audit & Regression Sweep
**Purpose:** Systematic review of remaining hot paths and verification that P0–P5 features still work correctly after P6 changes.

**Hot path audit checklist:**
- [ ] Artwork image decoding — confirm it runs off main thread (check `AlbumArtworkView`, `LockScreenArtworkProvider`).
- [ ] Theme/palette extraction (`ArtworkThemeProvider`) — confirm background dispatch.
- [ ] Lock screen metadata updates — confirm metadata sequencing (`metadataSequence` in `PlaybackViewModel`) prevents stale artwork during rapid skips.
- [ ] Offline manifest access (`OfflinePlaybackIndex`) — confirm O(1) dictionary lookup and thread-safe locking.
- [ ] Queue persistence after force-quit — confirm P6.2 debounce doesn't lose data (verify `persistImmediately()` is called on background transition).
- [ ] Navigation back-stack — confirm P4 disk-first cache returns instantly without reload churn.
- [ ] Remote commands through lock/unlock cycles — confirm P5 hardening holds after P6 changes.
- [ ] Duplicate `fetchTracks` calls — confirm no redundant network requests for the same album.

**Regression test scenarios (manual, device):**
1. Play album from library → sequential playback, no skips or glitches.
2. Skip forward/backward 20 times rapidly → no desync, correct metadata.
3. Seek within track → accurate position, scrubber stable.
4. Background audio → continues playing through lock/unlock.
5. Interruption (phone call simulation) → pause/resume correctly.
6. Download album → play offline → verify local playback.
7. Queue management: Play Now, Play Next, Play Later, Clear Queue → all correct.
8. Force-quit/relaunch → queue and position restored, no auto-play.
9. Browse Collections → Album → Back → no reload spinner.

**Deliverable:** Document findings in PR description. Fix any issues found as small follow-up commits.

---

#### P6.8 — PlaybackDomain Consolidation Report (Document Only)
**Purpose:** Written analysis of the split-ownership architecture and a concrete plan for consolidating into a single `PlaybackDomain` actor. No code changes.

**Report structure (write to `docs/playback-domain-consolidation-plan.md`):**

1. **Current architecture:** Split ownership across `PlaybackEngine` (audio player, skip debouncing, item tracking — 317 lines), `QueueManager` (queue entries, persistence, insert/remove — 368 lines), and `PlaybackViewModel` (coordination, lock screen, remote commands — 839 lines). Document state flow and desync risk points.

2. **P1 design review:** What commit `8790d4f` implemented — single `PlaybackDomain` actor owning queue + playback state, `PlaybackSnapshot` immutable read model via `AsyncStream`, 427 lines replacing Engine + QueueManager. Review the 27 unit tests it added.

3. **Gap analysis:** Features added in P4/P5 that P1 branch does not have:
   - Disk-first library cache (P4)
   - Skip debouncing with 300ms settle (P5)
   - Scrubber stability with seek cooldown (P5)
   - Metadata sequencing for stale artwork prevention (P5)
   - Remote command idempotency (P5)
   - Lock screen artwork caching (P5)
   - Audio session interruption handling (P5)

4. **Recommended migration approach:** Evaluate two options:
   - **Option A — Cherry-pick P1 actor into P6 branch:** High merge conflict risk given P4/P5 divergence. All P5 hardening features must be re-integrated into the actor.
   - **Option B — Incremental extraction (recommended):** Move queue state ownership into actor first, then playback coordination, then deprecate split ownership. Each step is a small PR.

5. **Proposed P7 scope:** Concrete sub-phases for the incremental migration.

**File to create:**
- `docs/playback-domain-consolidation-plan.md`

### Scope
- P6.1: Lazy Up Next rendering (LazyVStack + item limit).
- P6.2: Background queue persistence (async + debounce).
- P6.3: Fast shuffle start (two-phase queue: immediate playback + background fill).
- P6.4: Parallel track fetching (TaskGroup replacing sequential loop).
- P6.5: Latency instrumentation (durationMs events in diagnostics).
- P6.6: Baseline comparison workflow (capture instructions + Python script).
- P6.7: Code audit and regression sweep.
- P6.8: PlaybackDomain consolidation report (document only).

### Delivery Order
```
P6.1 (Lazy Up Next)          ← independent, quick win
P6.2 (Background Persist)    ← independent, quick win, parallel with P6.1
P6.4 (Parallel Fetching)     ← prerequisite for P6.3
P6.3 (Fast Shuffle)          ← depends on P6.4
P6.5 (Latency Instrumentation) ← after P6.3 (instruments the new shuffle path)
P6.6 (Baseline Workflow)     ← after P6.5
P6.7 (Code Audit)            ← final pass after P6.1–P6.5
P6.8 (Consolidation Report)  ← independent, can be written anytime
```

### Exit Criteria
- Large collection shuffle starts audio within a few seconds (not 22+).
- Up Next UI scrolls smoothly with thousands of queued tracks.
- Queue persistence does not block the UI.
- Diagnostics capture latency measurements for key operations.
- No blocking regressions in playback, offline, or navigation.
- PlaybackDomain consolidation plan documented for future phase.

### Manual Test Script
1. Shuffle "Key Albums" collection (thousands of tracks).
2. Verify audio starts within a few seconds.
3. Scroll Up Next — verify smooth scrolling.
4. Skip 20 times rapidly — verify no desync.
5. Force-quit and relaunch — verify queue restored.
6. Repeat P0 baseline scenario and compare diagnostics.
7. Confirm no visual/state desync during long skip sessions.

### Approval Checkpoint
- "Approve P6 release candidate."

## Fast Follow 1 - Gapless/Crossfade Foundation
### Branch
- `codex/rewrite-ff1-gapless-crossfade-scaffold`

### Scope
- Add architecture scaffolding for gapless/crossfade transitions.
- Add config surfaces and diagnostics markers for transition decisions.

### Exit Criteria
- No regressions to core playback.
- Transition infrastructure is ready for behavior tuning.

### Manual Test Script
1. Enable transition scaffolding setting.
2. Play sequential tracks across mixed formats/bitrates.
3. Verify stable playback and diagnostics events for transition path.

## Per-Phase Delivery Contract (Agentic Workflow)
Every phase delivery must include:
1. Implemented scope vs deferred scope.
2. Changed files/modules.
3. Unit test results (agent-run).
4. Device manual QA checklist with pass/fail notes.
5. Diagnostics samples and metric deltas.
6. Explicit "ready for approval" checkpoint.
