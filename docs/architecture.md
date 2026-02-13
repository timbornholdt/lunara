# Lunara Architecture Status

## Status (2026-02-13)
Phase 1 features are complete. The app is transitioning to a phased full rewrite of playback, offline, and library data architecture.

## Why Rewrite
- Current playback behavior shows state-consistency issues under skip/relaunch conditions.
- Current browse behavior can feel reload-heavy on navigation backstack.
- Hot-path offline lookup and download mechanics need performance-focused redesign.

## Current Risk Areas
1. Playback state is owned by multiple components (engine + queue + UI context).
2. Relaunch playback priming has edge-case sequencing risks.
3. Detail pages trigger network reload behavior on re-entry.
4. Snapshot model does not enforce manual-refresh-only semantics.
5. Offline lookups and downloads need hot-path and memory improvements.

## Target Architecture
- A single actor-owned playback domain as source of truth.
- Durable queue and resume state managed by that domain.
- Stream-oriented offline downloader with optimized local index lookup.
- Disk-first repository for library navigation with explicit pull-to-refresh.
- Diagnostics-first instrumentation and metric-driven phase validation.

## Delivery Rules
- New `codex/...` branch per phase.
- One scoped phase at a time.
- Stop for explicit user approval after each phase.
- Agent runs unit tests.
- User validates via manual device script (iPhone 15 Pro, iOS 26.2).

## Plan Reference
- `docs/features/playback-rewrite-phased-cutover-plan.md`
- `docs/project-plan.md` (Phase 2)
