# PlaybackDomain Consolidation Plan

## 1. Current Architecture

Playback state is split across three owners on the current P5 branch (`codex/rewrite-p5-background-remote`):

### PlaybackEngine (326 lines)
- Owns: AVPlayer queue, current index, elapsed time, `isPlaying` flag
- Manages: skip debouncing (300ms settle), item failure/fallback retry, source resolution
- Publishes state via `onStateChange: ((NowPlayingState?) -> Void)?` callback
- Not an actor — runs on caller's context

### QueueManager (387 lines)
- Owns: `QueueState` (entries, currentIndex, elapsedTime, isPlaying), durable persistence
- Manages: insert modes (playNow/playNext/playLater), duplicate burst blocking, entry removal
- `@MainActor` class with synchronous in-memory state + debounced background persistence (P6.2)

### PlaybackViewModel (854 lines)
- Coordinates between Engine and QueueManager
- Owns: lock screen metadata, remote command handling, theme resolution, artwork caching
- Handles: relaunch priming, queue mutation application, offline state hooks
- `@MainActor` `ObservableObject`

### State Flow
```
User Action -> PlaybackViewModel -> PlaybackEngine.play/skip
                                 -> QueueManager.setState/insert
PlaybackEngine.onStateChange -> PlaybackViewModel.handleStateChange
                             -> QueueManager.updatePlayback
                             -> NowPlayingInfoCenter.update
```

### Desync Risk Points
1. Engine's `currentIndex` and QueueManager's `currentIndex` are updated at different times during skip operations.
2. `handleStateChange` receives periodic timer updates (~1/sec) that update QueueManager, creating unnecessary persistence churn.
3. Relaunch priming reads from QueueManager but engine is not yet initialized — `togglePlayPause` has a special `hasPrimedEngineFromQueue` path to handle this.
4. Queue mutations via `insertIntoQueue` may trigger `play()` which resets engine state, while QueueManager already has the updated state.

## 2. P1 Design Review

Commit `8790d4f` introduced a single `PlaybackDomain` actor (427 lines) that replaces both PlaybackEngine and QueueManager:

### Key Design Decisions
- **Single actor** owns queue entries, current index, playback state, elapsed time, and persistence
- **`PlaybackSnapshot`** immutable value type published via `AsyncStream` — UI subscribes to one stream
- Queue progression, skip logic, and fallback retry all live inside the actor
- 27 unit tests covering play, skip, insert, remove, persistence, and edge cases

### What P1 Simplified
- No more split-ownership coordination in ViewModel (472 lines, down from 839)
- Single source of truth for queue index — eliminates desync risk
- Persistence owned by the domain, not a separate manager
- ViewModel becomes a thin adapter: subscribe to snapshot, update lock screen, handle remote commands

## 3. Gap Analysis

Features added in P4/P5 that the P1 branch (`8790d4f`) does not have:

| Feature | Phase | Description |
|---------|-------|-------------|
| Disk-first library cache | P4 | `LibraryCacheStore` for collections/albums/artists with pull-to-refresh |
| Skip debouncing (300ms) | P5 | `scheduleSkip` in PlaybackEngine coalesces rapid next/previous |
| Scrubber stability | P5 | Seek cooldown (500ms) + scrub activity timeout (2s) in NowPlayingSheetView |
| Metadata sequencing | P5 | `metadataSequence` counter prevents stale artwork during rapid skips |
| Remote command idempotency | P5 | Remote handlers dispatch through `@MainActor` with diagnostics logging |
| Lock screen artwork caching | P5 | `LockScreenArtworkProvider` with per-album cache key tracking |
| Audio session interruption | P5 | `AudioSessionManager` pause/resume on phone call interruption |
| Background queue persistence | P6.2 | Debounced async persistence with `persistImmediately()` on background |
| Parallel track fetching | P6.4 | `withThrowingTaskGroup` in CollectionAlbumsViewModel |
| Two-phase shuffle | P6.3 | Immediate playback from first 5 albums, background fill for rest |
| Latency instrumentation | P6.5 | `operationStartTimes` in PlaybackEngine, shuffle phase timing |

## 4. Recommended Migration Approach

### Option A — Cherry-Pick P1 Actor Into P6 Branch
- **Pros:** Clean actor design already proven with 27 tests
- **Cons:** High merge conflict risk. P4/P5/P6 divergence means every hardening feature must be re-integrated. The P1 PlaybackViewModel is 472 lines vs current 854 — significant structural changes. Risk of regression.
- **Verdict:** Not recommended given current divergence.

### Option B — Incremental Extraction (Recommended)
Move ownership gradually into an actor, one responsibility at a time. Each step is a small PR with targeted tests.

**Advantages:**
- Each step is independently testable and reviewable
- No big-bang merge conflict
- P5/P6 hardening features are preserved throughout
- Can pause migration at any step without leaving broken state

## 5. Proposed P7 Scope — Incremental Migration

### P7.1 — Extract QueueDomain Actor
- Move `QueueManager` state management into `QueueDomain` actor
- Actor owns: entries, currentIndex, insert/remove/clear operations, debounced persistence
- PlaybackViewModel calls actor methods instead of QueueManager
- PlaybackEngine unchanged
- **Tests:** Migrate existing QueueManagerTests to actor-based tests

### P7.2 — Unify Index Ownership
- Remove `currentIndex` tracking from PlaybackEngine
- QueueDomain becomes the single source of truth for queue index
- Engine receives index updates from domain, not the other way around
- **Risk:** Skip debouncing must be coordinated — either move into domain or keep engine as debounce-only relay
- **Tests:** Verify skip sequences produce correct index in domain

### P7.3 — Merge Playback Coordination Into Domain
- Move `play()`, `togglePlayPause()`, `skipToNext/Previous()` coordination into domain
- Domain dispatches to player adapter (not engine)
- PlaybackEngine is eliminated — player adapter is owned by domain
- **Tests:** Port PlaybackEngine skip/fallback tests to domain

### P7.4 — Slim Down PlaybackViewModel
- ViewModel subscribes to domain's snapshot stream
- Remove state mirroring — ViewModel only handles UI concerns:
  - Lock screen metadata publishing
  - Remote command registration
  - Theme resolution
  - Error message presentation
- **Target:** ViewModel under 400 lines

### P7.5 — Snapshot Stream + Metadata Sequencing
- Publish `PlaybackSnapshot` via `AsyncStream` from domain
- Integrate metadata sequencing (currently `metadataSequence` counter) into snapshot versioning
- Ensure stale artwork prevention works with the new stream model
- **Tests:** Rapid skip sequences produce correct metadata ordering

### Delivery Order
```
P7.1 (QueueDomain Actor)          ← foundation, low risk
P7.2 (Unify Index Ownership)      ← eliminates desync risk
P7.3 (Merge Playback into Domain) ← eliminates PlaybackEngine
P7.4 (Slim ViewModel)             ← cleanup, UI-only concerns
P7.5 (Snapshot Stream)            ← final architecture alignment
```

### Exit Criteria for P7
- Single actor owns all playback + queue state
- ViewModel is a thin subscriber (<400 lines)
- No split-ownership desync risk
- All P5/P6 hardening features preserved
- Existing manual test scenarios pass without regression
