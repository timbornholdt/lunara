# Incremental Library + Artwork Sync Roadmap

Updated: February 18, 2026

## Goal

Stop full cache replacement during refresh. Keep existing albums/artwork unless they changed, and only fetch/store the minimum needed to reconcile with Plex.

This roadmap is written for future implementation bots and should be executed in small, reviewable sessions.

## Why This Exists

- Current refresh behavior deletes and reinserts album/track rows during each successful refresh.
- Artwork files are cached on disk, but metadata refresh still behaves like a full rewrite.
- This library is private and changes infrequently, so sync should optimize for low churn and predictable behavior.

## Non-Negotiable Constraints

- Follow `/Users/timbornholdt/Repos/Lunara/README.md` architecture boundaries.
- Keep work inside Library domain and wiring points only.
- Protocol-first changes before concrete implementation.
- No new dependencies.
- Preserve current UX rule: cached data remains usable when refresh fails.
- Do not change shared types without explicit approval.

## Current Baseline (for orientation)

- Refresh orchestration: `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo.swift`
- Full replacement write path: `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore.swift`
- Artwork cache pipeline: `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Artwork/ArtworkPipeline.swift`
- App refresh fallback behavior: `/Users/timbornholdt/Repos/Lunara/Lunara/App/AppCoordinator.swift`

## Target End State

- Album metadata updates are row-level and incremental.
- Deleted albums are pruned deliberately (not by wiping all tables first).
- Track updates are incremental and tied to changed albums.
- Artwork is retained for unchanged albums and refreshed only when needed.
- Refresh cadence reflects low-churn library behavior.
- If Plex supports conditional validation headers, unchanged refreshes skip parse/write work.

## Delivery Plan

## Stage 1: Define Sync Contracts (Protocol-First)

Status: Completed on February 18, 2026.

### Deliverables

- Extend `LibraryStoreProtocol` with incremental APIs:
  - Upsert/merge albums.
  - Upsert/merge tracks.
  - Mark rows seen during a sync run.
  - Prune rows not seen in the current run.
  - Persist sync metadata/checkpoints.
- Define a Library-domain sync run model (not in Shared types).

### Notes

- Keep existing methods until migration is complete.
- Document transaction guarantees in protocol comments.
- Implemented in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreProtocol.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryStoreProtocolTests.swift`
- `LibraryStore` incremental APIs are currently explicit Stage 1 placeholders that throw `LibraryError.operationFailed` until Stage 2 GRDB reconciliation is implemented.

## Stage 2: Migrations + Incremental Store Engine

Status: Completed on February 18, 2026.

### Deliverables

- Add GRDB migration for sync bookkeeping fields/tables (for example: last-seen marker and sync metadata).
- Implement transactional store methods for:
  - Album upsert by `plexID`.
  - Track upsert by `plexID`.
  - Prune stale rows after successful reconciliation.
- Preserve metadata needed for diagnostics (last successful refresh, counters).

### Notes

- Transactions must ensure partial writes never leave the cache inconsistent.
- Maintain existing ordering/query behavior for paging.
- Implemented in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreMigrations.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreRecords.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore+IncrementalSync.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryStoreIncrementalSyncTests.swift`
- Added migration `v3_incremental_sync_bookkeeping` with per-row seen markers and checkpoint table, then implemented transactional upsert/mark/prune/checkpoint/complete methods behind `LibraryStoreProtocol`.

## Stage 3: Repository Reconciliation Flow

### Deliverables

- Replace full replacement refresh path with reconciliation logic in `LibraryRepo`.
- Compute and apply row-level categories:
  - new
  - changed
  - unchanged
  - deleted
- Keep current error behavior: failures surface to UI, stale cache remains available.

### Notes

- Keep artists/collections behavior aligned with current API availability.
- Preserve dedupe behavior where it already exists.

## Stage 4: Artwork Incremental Behavior

### Deliverables

- During reconciliation, detect artwork reference changes (for example `thumbURL` changes).
- Only invalidate/refetch artwork when:
  - artwork reference changed, or
  - cached file/path is missing.
- Prune artwork mappings/files for albums removed from the library.

### Notes

- Keep existing LRU eviction and disk-first load semantics.
- Do not block metadata refresh on artwork warmup.

## Stage 5: Conditional Request Feasibility Study

### Purpose

Determine whether this specific Plex deployment reliably supports HTTP validators for album refresh optimization.

### Research Tasks

- Instrument album refresh responses to log/record:
  - `ETag`
  - `Last-Modified`
  - cache directives
- Persist observations in local diagnostics metadata.
- Run multiple refreshes with no library changes and with known library changes.
- Attempt conditional requests (`If-None-Match` and/or `If-Modified-Since`) and record whether `304 Not Modified` is returned consistently.

### Decision Gate

- If validators are stable and `304` behavior is reliable, implement conditional request handling.
- If not reliable, retain incremental reconciliation without conditional short-circuiting.

## Stage 6: Conditional Request Integration (Only If Gate Passes)

### Deliverables

- Store validator metadata per relevant endpoint.
- Send conditional headers on refresh.
- On `304`: skip parse/write/artwork warmup.
- On `200`: proceed with normal incremental reconciliation and update validators.

## Low-Churn Refresh Policy

Because this library changes infrequently:

- App launch refresh should be freshness-window based (for example, only auto-refresh if older than 12-24 hours).
- Pull-to-refresh remains an explicit forced refresh.
- Maintain a user-visible "last refreshed" value in diagnostics/debug UI.

This reduces unnecessary network work even before conditional requests are proven.

## Testing Strategy

## Unit Tests (Required)

- Store upsert behavior:
  - inserts new albums/tracks
  - updates changed rows
  - keeps unchanged rows stable
- Prune behavior:
  - removes deleted albums/tracks
  - leaves expected rows intact
- Repository reconciliation:
  - applies new/changed/deleted correctly
  - keeps stale cache when network fails
- Artwork behavior:
  - unchanged `thumbURL` does not invalidate cache
  - changed `thumbURL` invalidates and refetches
  - deleted album removes artwork mapping/file
- Conditional path (if implemented):
  - `304` path skips writes
  - `200` path updates data and validator metadata

## Regression Coverage

- Paging still works for 2,000+ albums.
- Library grid remains usable while offline with cached content.
- Existing dedupe behavior remains correct.

## Manual QA Checklist (Device)

1. Launch app with network available and existing cache; verify albums load quickly.
2. Trigger refresh without server-side library changes; verify no broad re-download behavior and no visible churn.
3. Modify one album in Plex (metadata or artwork), refresh, verify only that album updates.
4. Remove one album in Plex, refresh, verify it disappears locally and associated artwork is pruned.
5. Disconnect network, trigger refresh, verify cached albums remain visible and error banner appears.
6. Relaunch app and verify artwork previously seen loads from disk cache.

## Suggested Session Slicing for Future Bots

1. Contract + migration design review.
2. Store incremental write implementation + tests.
3. Repo reconciliation implementation + tests.
4. Artwork incremental invalidation + tests.
5. Conditional feasibility instrumentation + diagnostics.
6. Conditional integration (only if viability confirmed).

Each session should stay within one module and end with passing tests plus a short QA checklist.

## Out of Scope

- Webhook/event-driven sync.
- New backend services.
- Cross-domain refactors.
- Performance tricks unrelated to incremental sync correctness.
