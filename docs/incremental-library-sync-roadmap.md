# Incremental Library + Artwork Sync Roadmap

Updated: February 18, 2026

## Goal

Stop full cache replacement during refresh and move the app to a single shared, cache-backed library read model.

The cache should be incrementally reconciled from Plex, then reused across all screens (albums grid, album detail, collection detail, up next, now playing context, and debug/diagnostics) without each screen refetching remote content.

This roadmap is written for future implementation bots and should be executed in small, reviewable sessions.

## Why This Exists

- Refresh now performs incremental metadata + artwork reconciliation in the Library domain.
- UI behavior still depends too much on paginated view-level loading state for some experiences (for example search across all albums).
- Long-term architecture requires the local store to be the canonical app-wide source for library reads, with refresh acting as background maintenance.
- This library is private and changes infrequently, so the app should optimize for cache reuse, low churn, and predictable startup behavior.

## Non-Negotiable Constraints

- Follow `/Users/timbornholdt/Repos/Lunara/README.md` architecture boundaries.
- Keep work inside Library domain plus approved wiring points (AppRouter and views consuming Library-domain read APIs).
- Protocol-first changes before concrete implementation.
- No new dependencies.
- Preserve current UX rule: cached data remains usable when refresh fails.
- Do not change shared types without explicit approval.

## Current Baseline (for orientation)

- Refresh orchestration: `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo.swift`
- Incremental store engine: `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore+IncrementalSync.swift`
- Artwork cache pipeline: `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Artwork/ArtworkPipeline.swift`
- App refresh fallback behavior: `/Users/timbornholdt/Repos/Lunara/Lunara/App/AppCoordinator.swift`
- Album grid view-model read behavior: `/Users/timbornholdt/Repos/Lunara/Lunara/Views/Library/LibraryGridViewModel.swift`

## Target End State

- Album and track metadata updates are row-level and incremental.
- Deleted entities are pruned deliberately (not by wiping all tables first).
- Artwork is retained for unchanged albums and refreshed only when needed.
- A single Library-domain cached catalog is the default source for app reads.
- Screens query/filter/sort against cached data (or cached slices), not remote fetches.
- Refresh updates cache in place and publishes read-model updates without forcing full UI reload semantics.
- If Plex supports conditional validation headers, unchanged refreshes can skip parse/write work.

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

Status: Completed on February 18, 2026.

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
- Implemented in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo+RefreshReconciliation.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryRepoTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryRepoTestDoubles.swift`
- `LibraryRepo.refreshLibrary` now:
  - fetches remote albums + tracks, dedupes with existing canonicalization rules,
  - computes row-level `new/changed/unchanged/deleted` deltas for albums/tracks,
  - persists delta counts as sync checkpoints,
  - applies incremental store APIs (`begin`, `upsert`, `mark seen`, `prune`, `complete`),
  - preserves existing stale-cache-on-failure behavior by only mutating cache after successful remote fetch and by propagating failures.

## Stage 4: Artwork Incremental Behavior

Status: Completed on February 18, 2026.

### Deliverables

- During reconciliation, detect artwork reference changes (for example `thumbURL` changes).
- Only invalidate/refetch artwork when:
  - artwork reference changed, or
  - cached file/path is missing.
- Prune artwork mappings/files for albums removed from the library.

### Notes

- Keep existing LRU eviction and disk-first load semantics.
- Do not block metadata refresh on artwork warmup.
- Implemented in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo+RefreshReconciliation.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo+AlbumMetadata.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryRepoTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryRepoTestDoubles.swift`
- `LibraryRepo` artwork refresh is now incremental:
  - invalidates album artwork cache when `thumbURL` changes,
  - skips refetch for unchanged `thumbURL` when cached thumbnail path exists on disk,
  - forces warmup only for new albums, changed artwork references, or missing cached files,
  - invalidates artwork for pruned/deleted album IDs from sync prune results,
  - keeps invalidation/warmup best-effort in an async task so metadata refresh completion is not blocked.

## Stage 5: App-Wide Cached Catalog Adoption (Up Next)

Status: Up next.

### Purpose

Make the incremental cache the primary read path for the entire app so all screens operate on one consistent local catalog and refresh behavior becomes background reconciliation instead of per-screen fetch behavior.

### Deliverables

- Define protocol-first read-model contract(s) in Library domain for catalog access.
  - Recommended shape: a `LibraryCatalog` (or equivalent) that exposes cached album/artist/collection reads, filtering, and pagination slices.
  - Include APIs for full-library album search (title + artist) so search is not limited to preloaded pages.
- Implement catalog loading from `LibraryStore` as startup/bootstrap behavior.
  - Initial view data should come from cache immediately.
  - Refresh should merge incremental updates into the same in-memory model (or read-through store query layer) without throwing away visible state.
- Migrate screen data flows to catalog-backed reads:
  - Albums grid/listing and search.
  - Album detail context hydration.
  - Collection detail and artist-related views.
  - Up next queue metadata lookups.
  - Now playing metadata/artwork lookups.
- Keep action boundaries unchanged:
  - Views still send actions through `AppRouter`.
  - Library domain remains source for library metadata.
  - Music domain remains source for playback state.

### Implementation Notes

- This is a cross-screen read-path migration, but still one module at a time.
- Avoid view-local source-of-truth caches that diverge from store-backed catalog state.
- Keep paging for rendering performance, but paging must be derived from a full cached dataset/queryable store so search and detail lookups can operate over all albums.
- Do not introduce Music-domain imports into Library-domain types (or vice versa).
- If needed, split into sub-sessions:
  - 5a contracts + catalog model
  - 5b album grid migration
  - 5c detail/up-next/now-playing metadata adoption

### Decision Gate

- Stage 5 is complete when no user-facing screen relies on remote fetch as its primary metadata source during normal navigation.
- App cold launch with existing cache should render key views without network.

### Locked Decisions (February 18, 2026)

- Architecture choice: store-backed query service (not a long-lived in-memory catalog source of truth).
- Album search scope: `album.title` and `album.artistName` only.
- Launch behavior: always render cached data first, then reconcile in background.
- Missing metadata behavior: allow remote fallback fetch when local cache miss occurs.
- Stage 5 scope for artists/collections: backend/query readiness only (no new artists/collections UI screens in this stage).
- Artist/collection search scope:
  - Artists: `artist.name` and `artist.sortName`.
  - Collections: `collection.title`.
- Query ordering: query APIs return fully sorted results (screens should not re-sort by default).
- Queue consistency: if a track referenced by queue state no longer resolves in cache/remote metadata, remove it from queue.
- Playback behavior for removed current item: skip to next valid queue item automatically.

### Stage 5 Execution Plan (Approved)

1. Stage 5A: Protocol contracts
   - Extend `LibraryStoreProtocol` and `LibraryRepoProtocol` with query-first APIs:
     - `searchAlbums(query:)`
     - `searchArtists(query:)`
     - `searchCollections(query:)`
     - `track(id:)`
     - `collection(id:)`
   - Keep existing pagination APIs for rendering slices.
   - Define sorted-output guarantees in protocol comments.

2. Stage 5B: Store query engine
   - Implement query/search APIs in `LibraryStore` (GRDB-backed).
   - Add/adjust indexes as needed for title/artist/collection search performance.
   - Ensure case/diacritic-insensitive matching behavior.
   - Add direct `track(id:)` lookup path required for queue metadata reconciliation.

3. Stage 5C: Repo read layer + remote fallback
   - Wire new query APIs through `LibraryRepo`.
   - Implement remote fallback for metadata misses (including `track(id:)`) and preserve cache-first semantics.
   - Keep current stale-cache-on-failure guarantees.

4. Stage 5D: Albums view migration
   - Refactor `LibraryGridViewModel` search path to query full cached catalog instead of filtering loaded pages.
   - Preserve page-based rendering behavior for scrolling performance.

5. Stage 5E: Queue reconciliation for missing tracks
   - Add queue reconciliation flow after refresh/startup to drop queue items whose `trackID` no longer resolves.
   - When current item is removed, auto-advance to the next valid queue item.
   - Keep orchestration in AppRouter/coordinator wiring to respect domain boundaries.

6. Stage 5F: Regression hardening + status update
   - Add tests for full-catalog search behavior and queue reconciliation behavior.
   - Validate cache-first reads across existing surfaces (albums, album detail, debug/queue metadata paths).
   - Update this roadmap Stage 5 status and completion notes when done.

## Stage 6: Conditional Request Feasibility Study

### Purpose

Determine whether this specific Plex deployment reliably supports HTTP validators for refresh optimization.

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

## Stage 7: Conditional Request Integration (Only If Gate Passes)

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
- App-wide cached catalog behavior:
  - search scans full cached catalog, not just rendered page slices
  - detail/up-next/now-playing views resolve metadata from cache without remote dependency
  - incremental refresh publishes updates without forcing full cache reset semantics
- Conditional path (if implemented):
  - `304` path skips writes
  - `200` path updates data and validator metadata

## Regression Coverage

- Paging still works for 2,000+ albums.
- Library grid remains usable while offline with cached content.
- Existing dedupe behavior remains correct.
- App relaunch reuses local cache as primary source before refresh completes.

## Manual QA Checklist (Device)

1. Launch app with network disabled after a prior successful sync; verify albums, album detail, collections, up next metadata, and now playing metadata render from cache.
2. Re-enable network, trigger refresh with no server-side changes; verify no visible cache reset/reload flash and no broad artwork churn.
3. Search albums by artist and title terms that are not in first rendered pages; verify results still appear.
4. Modify one album in Plex (metadata or artwork), refresh, verify only that album updates across grid and detail surfaces.
5. Remove one album in Plex, refresh, verify it disappears locally and associated artwork is pruned.
6. Disconnect network, trigger refresh, verify cached data remains visible and error banner appears.

## Suggested Session Slicing for Future Bots

1. Stage 5a: catalog read-model contracts and bootstrap wiring.
2. Stage 5b: album grid/search migration to full-cache-backed reads.
3. Stage 5c: album detail, collection detail, up-next, and now-playing metadata migration.
4. Stage 5d: regression tests + offline QA pass for app-wide cache-first behavior.
5. Stage 6: conditional feasibility instrumentation + diagnostics.
6. Stage 7: conditional integration (only if viability confirmed).

Each session should stay within one module and end with passing tests plus a short QA checklist.

## Out of Scope

- Webhook/event-driven sync.
- New backend services.
- Cross-domain architecture violations.
- Performance tricks unrelated to incremental sync correctness.
