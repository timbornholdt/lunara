# Repo Inventory

## Overview (Current State)
Lunara is a SwiftUI iOS app for a single-user Plex music library with implemented Phase 1 capabilities: auth, browse, playback, queue persistence, lock-screen controls, offline downloads, and settings flows. The app is now entering a phased full rewrite of playback/offline/library architecture for reliability and performance.

## Code Structure
- App entry and root routing:
  - `Lunara/LunaraApp.swift`
  - `Lunara/ContentView.swift`
- UI views and view models:
  - `Lunara/UI/Views/`
  - `Lunara/UI/`
- Playback domain (current implementation):
  - `Lunara/Playback/`
- Offline/download domain (current implementation):
  - `Lunara/Offline/`
- Plex API and networking:
  - `Lunara/Plex/`
- Snapshot and caches:
  - `Lunara/LibrarySnapshot/`
  - `Lunara/Artwork/`
- Tests:
  - `LunaraTests/`

## Current Runtime Patterns
- UI: SwiftUI + `NavigationStack` + MVVM-oriented view models.
- Concurrency: mixed model (`@MainActor` view models, actors in offline layer, callback-driven playback internals).
- Playback: AVQueuePlayer adapter + custom engine + separate queue manager + now-playing context model.
- Offline: actor-backed download coordinator + JSON manifest + file store.
- Library caching: single snapshot store with cached-first render and immediate live refresh in several browse paths.

## Key Architecture Findings (2026-02-13)
1. Playback state ownership is fragmented across playback engine, queue manager, and UI context state.
2. Relaunch priming/toggle behavior has risk of state desync and apparent no-play behavior.
3. Collection/album/artist detail screens are implemented with load-on-entry behavior that can re-fetch on back navigation.
4. Browse entry paths currently snapshot-load and then live-refresh automatically, which conflicts with manual-refresh-only preference.
5. Offline source resolution performs manifest load/decoding on hot paths, likely increasing queue-start latency.
6. Downloader currently uses full in-memory fetch (`URLSession.data`) rather than streaming writes.
7. Collection playback track fetch path is serial and may impact startup-to-first-audio latency.

## Testing and Quality
- Unit tests are extensive across playback, queue, offline coordinator, and browse view models.
- Manual QA remains mandatory for real device behavior validation.
- Active rewrite workflow requires explicit per-phase manual test scripts and approval checkpoints.

## Active Architecture Direction
Reference: `docs/features/playback-rewrite-phased-cutover-plan.md`

- Move to a single concurrency-owned playback domain as source of truth.
- Replace ad hoc state coupling with immutable playback read models for UI.
- Rebuild durable queue lifecycle semantics for force-quit resilience.
- Rewrite download engine for stream-oriented file handling and low-latency local lookup.
- Rebuild library repository as disk-first with explicit pull-to-refresh semantics.
- Harden background/remote control lifecycle behavior.
- Add diagnostics-first instrumentation and compare phase-over-phase metrics.

## Ongoing Instructions for Agents
1. Treat `docs/features/playback-rewrite-phased-cutover-plan.md` as the source of truth for rewrite sequencing.
2. Use one `codex/...` branch per phase and stop for explicit user approval between phases.
3. Keep each phase PR-sized and scoped to one cutoff objective.
4. Provide device manual QA checklists and expected outcomes in every phase handoff.
5. Run unit tests before phase handoff; report results and any gaps.
6. Prioritize reliability and state consistency over new UX behavior.
