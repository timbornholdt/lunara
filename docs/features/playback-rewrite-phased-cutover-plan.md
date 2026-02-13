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

### Scope
- Remove residual hot-path latency and redundant work.
- Compare diagnostics metrics to phase 0 baseline.
- Complete final regression sweep for playback/offline/navigation.

### Exit Criteria
- Metrics improve materially over baseline.
- No blocking regressions in manual playback and browse behavior.

### Manual Test Script
1. Repeat phase 0 baseline scenario.
2. Verify improved startup-to-first-audio and skip responsiveness.
3. Confirm no visual/state desync during long skip sessions.

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
