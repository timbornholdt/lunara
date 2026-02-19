# Incremental Library + Artwork Sync Roadmap

Updated: February 19, 2026

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
- Relational metadata queries are first-class in cache (for example tags, artists, collections, and playlists with stable IDs and join tables).
- Album exploration queries such as "all ambient albums with calm mood released between January 1, 1980 and December 31, 1994" are resolved locally without remote dependency during normal navigation.

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

Status: In progress (Stages 5A-5L completed as of February 19, 2026; 5M pending).

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

### Locked Decisions (February 19, 2026)

These decisions extend Stage 5 toward a normalized relational cache model and are approved for future implementation sessions.

- **Normalization direction:** evolve `LibraryStore` to an entity + join-table graph for long-term stability, even if this requires deleting or replacing some current code.
- **Migration policy:** this app is single-user; strict backward compatibility migration safety is not required. Prefer simple, deterministic schema evolution over preserving every legacy shape.
- **Tag model:** tags are stored and queried separately by kind (`genre`, `style`, `mood`) and normalized for case/diacritic-insensitive behavior.
- **Tag combinator semantics:** default to `ALL` semantics within each filter bucket (for example mood must include every requested mood tag).
- **Text search semantics:** substring search.
- **Year-range semantics:** inclusive bounds. Example: `1980...1994` means January 1, 1980 through December 31, 1994.
- **Missing year behavior:** albums without year are excluded from year-bounded queries.
- **Artist identity:** use Plex artist ID as canonical identity; album `artistName` remains display text.
- **Album artist roles:** defer role-specific modeling (primary/featured/etc.) for now.
- **Collection membership scope:** Plex collections only.
- **Tag scope for now:** album-level tags only (not track-level tags yet).
- **Track year fallback:** when track-level year filtering is added later, use album year unless Plex provides explicit track year.
- **Playlist readiness:** add playlist-capable relational schema now; preserve Plex ordering and duplicate items exactly as returned.
- **Query API shape:** one flexible filter API (not a growing set of one-off query methods).

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

Stage 5A status (completed February 18, 2026):
- Added Stage 5A query-service contracts to:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreProtocol.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepoProtocol.swift`
- Added non-5B placeholder conformances in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo.swift`
- Updated protocol test doubles and protocol/repo tests to compile against and cover new APIs.
- Stage 5B store query engine work intentionally not started in this session.

2. Stage 5B: Store query engine
   - Implement query/search APIs in `LibraryStore` (GRDB-backed).
   - Add/adjust indexes as needed for title/artist/collection search performance.
   - Ensure case/diacritic-insensitive matching behavior.
   - Add direct `track(id:)` lookup path required for queue metadata reconciliation.

Stage 5B status (completed February 19, 2026):
- Implemented GRDB-backed Stage 5B query APIs in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStore.swift`
- Added normalized search columns + indexes and migration backfill in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreMigrations.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreRecords.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Store/LibraryStoreSearchNormalizer.swift`
- Added direct Store query coverage for Stage 5B behavior in:
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryStoreQueryTests.swift`

3. Stage 5C: Repo read layer + remote fallback
   - Wire new query APIs through `LibraryRepo`.
   - Implement remote fallback for metadata misses (including `track(id:)`) and preserve cache-first semantics.
   - Keep current stale-cache-on-failure guarantees.

Stage 5C status (completed February 19, 2026):
- Wired query-service reads through `LibraryRepo` with cache-first behavior and remote fallback only on cache miss for:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepo.swift`
- Added album-detail targeted refresh API to refresh one album + tracks without forcing global refetch:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Library/Repo/LibraryRepoProtocol.swift`
- Added/updated cache-first + fallback coverage in:
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryRepoTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryRepoProtocolTests.swift`

4. Stage 5D: Albums view migration
   - Refactor `LibraryGridViewModel` search path to query full cached catalog instead of filtering loaded pages.
   - Preserve page-based rendering behavior for scrolling performance.

Stage 5D status (completed February 19, 2026):
- Migrated albums grid to full cached catalog reads on initial load and background refresh update:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Views/Library/LibraryGridViewModel.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Views/Library/LibraryGridViewModel+BackgroundRefresh.swift`
- Preserved explicit user-initiated refresh semantics (`pull-to-refresh` forces refresh then reloads cache).
- Added full-catalog search/read-path coverage in:
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryGridViewModelTests.swift`

5. Stage 5E: Queue reconciliation for missing tracks
   - Add queue reconciliation flow after refresh/startup to drop queue items whose `trackID` no longer resolves.
   - When current item is removed, auto-advance to the next valid queue item.
   - Keep orchestration in AppRouter/coordinator wiring to respect domain boundaries.

Stage 5E status (completed February 19, 2026):
- Added queue reconciliation orchestration in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Router/AppRouter.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/App/AppCoordinator.swift`
- Added queue-level reconcile behavior in:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Music/Queue/QueueManagerProtocol.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Music/Queue/QueueManager.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Music/Queue/QueueManager+Reconciliation.swift`
- Added queue reconciliation behavior tests in:
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/AppRouterTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/AppCoordinatorTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/QueueManagerTests.swift`

6. Stage 5F: Regression hardening + status update
   - Add tests for full-catalog search behavior and queue reconciliation behavior.
   - Validate cache-first reads across existing surfaces (albums, album detail, debug/queue metadata paths).
   - Update this roadmap Stage 5 status and completion notes when done.

Stage 5F status (completed February 19, 2026):
- Added targeted regression coverage for:
  - full-catalog search refresh behavior after background catalog updates,
  - queue reconciliation duplicate-ID lookup behavior,
  - queue reconciliation edge case when current item is removed and no next valid item exists,
  - startup cache-first coordinator path with empty queue metadata reconciliation no-op.
- Coverage added/updated in:
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/LibraryGridViewModelTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/AppRouterTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/QueueManagerTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/AppCoordinatorTests.swift`
- Stage 5 remains in progress pending Stage 5I+ reconciliation/query/UI milestones.

7. Stage 5G: Remote ingest parity for full metadata catalogs
   - Extend `LibraryRemoteDataSource` + `PlexAPIClient` with:
     - `fetchArtists()`
     - `fetchCollections()`
     - playlist fetch APIs (shape determined by Plex response payloads when implemented)
   - Update `LibraryRepo.refreshLibrary` orchestration so refresh can populate and persist artists/collections (and later playlists) in the same reconciliation run.
   - Keep launch/debug refresh behavior cache-first and stale-cache-safe.
   - Add integration tests proving debug-triggered/full refresh populates full metadata catalogs, not albums/tracks only.

Stage 5G status (completed February 19, 2026):
- Extended Library remote ingest contracts and Plex client support for:
  - `fetchArtists()`
  - `fetchCollections()`
  - playlist fetch API hooks.
- Updated `LibraryRepo.refreshLibrary` orchestration so artists + collections are fetched and persisted in the same refresh run as albums + tracks.
- Preserved existing cache-first launch/read behavior and stale-cache-on-failure refresh behavior.
- Added integration-style refresh coverage proving full metadata catalog ingest parity.

8. Stage 5H: Relational schema foundation (Store)
   - Add normalized entity/join tables in `LibraryStore` migration(s), likely including:
     - `tags` (`id`, `kind`, `name`, `normalizedName`)
     - `album_tags` (`albumID`, `tagID`)
     - `album_artists` (`albumID`, `artistID`)
     - `album_collections` (`albumID`, `collectionID`)
     - `playlists` and `playlist_items` (`playlistID`, `trackID`, `position`, preserving duplicates/order)
   - Add indexes for filter-heavy paths:
     - `tags(kind, normalizedName)`
     - `album_tags(tagID, albumID)`
     - `album_artists(artistID, albumID)`
     - `album_collections(collectionID, albumID)`
     - `playlists(plexID)` and `playlist_items(playlistID, position)`
   - Keep existing tables temporarily where needed; remove deprecated paths after parity tests pass.

Stage 5H status (completed February 19, 2026):
- Added relational schema foundation in `LibraryStore` for normalized entities and join-table modeling.
- Added baseline indexes needed for relational filter/query performance and stable playlist ordering lookups.
- Preserved deterministic migration behavior and existing cache-first/stale-cache-safe repository behavior.

9. Stage 5I: Reconciliation engine for relationships
   - Extend incremental sync bookkeeping to relationship rows so joins are upserted + pruned deterministically per run.
   - Ensure row + relationship pruning never leaves orphaned joins.
   - Canonicalize tags during ingest:
     - fold case/diacritics,
     - merge collisions into one canonical tag row per (`kind`, normalized value).
   - Treat artist/collection/playlists by Plex IDs as canonical keys.

10. Stage 5J: Flexible query API + query planner implementation
   - Add protocol-first filter contract(s) for album querying (for example `AlbumFilter`):
     - `textQuery` (substring),
     - `yearRange`,
     - `genreTagIDs`/`styleTagIDs`/`moodTagIDs` (ALL semantics),
     - optional artist/collection constraints for future reuse.
   - Implement GRDB-backed query planner in `LibraryStore` using joins + grouped/having semantics where required for ALL-tag matching.
   - Explicitly encode sort guarantees in protocol comments and tests.
   - Add test vectors for exact user-facing scenarios, including:
     - `genre = ambient AND mood = calm AND year 1980...1994`.

11. Stage 5K: UI/read-path adoption for relational filtering
   - Move album-screen filtering from view-local array filtering to store-backed flexible query APIs.
   - Remove page-sliced rendering from the primary album read path; load the full cached catalog immediately on screen entry and derive filtered/sorted views directly from cache-backed queries.
   - Ensure no normal navigation path requires remote metadata fetch when cache is present.

Stage 5K status (completed February 19, 2026):
- Migrated `LibraryGridViewModel` primary read path to `library.queryAlbums(filter: .all)` — full cached catalog loads immediately on screen entry, no pagination.
- Search filtering replaced from view-local array filter to `AlbumQueryFilter(textQuery:)` store-backed query via `library.queryAlbums(filter:)`.
- `loadNextPageIfNeeded()` is now a documented no-op; background refresh re-queries full catalog + active search via `applyBackgroundRefreshUpdateIfNeeded()`.
- All tests pass: `LibraryGridViewModelTests` (22 tests) and `LibraryStoreAlbumQueryPlannerTests` (4 tests).

12. Stage 5L: Playlist relational readiness pass
   - Persist playlist metadata and ordered items from Plex payloads.
   - Validate that order and duplicate entries are preserved exactly.
   - Expose protocol-first read APIs for future playlist screens (no UI required in this stage unless explicitly scoped).

Stage 5L status (completed February 19, 2026):
- Added `fetchPlaylists()` and `fetchPlaylistItems(playlistID:)` to `LibraryStoreProtocol` with sort/ordering guarantees documented in protocol comments.
- Implemented read APIs in `LibraryStore.swift` using raw SQL ordered by `title` (playlists) and `position ASC` (items).
- Added `playlists()` and `playlistItems(playlistID:)` to `LibraryRepoProtocol` with cache-semantics documented (no remote fallback — playlists are populated during `refreshLibrary` only).
- Implemented in `LibraryRepo.swift` delegating directly to the store.
- Updated all `LibraryStoreProtocol` conforming mocks in tests and added `playlists`/`playlistItems` stubs to all `LibraryRepoProtocol` test doubles.
- Added 9 new tests in `LunaraTests/LibraryStorePlaylistTests.swift` covering:
  - New playlist inserts with correct metadata,
  - Upsert-on-conflict updating existing playlists,
  - Position-order preservation exactly matching Plex order regardless of insert order,
  - Duplicate trackIDs at different positions remaining as distinct rows,
  - Stale playlist prune removing playlists and their items without orphaning,
  - Orphan cleanup after playlist pruned from a later sync run,
  - fetchPlaylists returns empty on fresh store,
  - fetchPlaylistItems returns empty for unknown playlist IDs,
  - fetchPlaylists sorts by title ascending.
- All 9 tests pass. Full project test suite passes.

13. Stage 5M: Cleanup + hardening
   - Remove superseded non-relational query code and obsolete schema paths.
   - Expand regression suite for relationship pruning, canonical tag merges, playlist ordering, and offline query correctness.
   - Update roadmap status and residual risks.

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
- Relational query behavior:
  - tag filters apply by kind (`genre`, `style`, `mood`) with ALL semantics within each kind
  - year-range filtering is inclusive and excludes unknown-year rows
  - canonicalized tag collisions merge to single normalized entities deterministically
  - no orphan join rows after prune
- Playlist relational behavior:
  - playlist item ordering is preserved exactly
  - duplicate playlist entries remain intact
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
3. Search albums by artist and title terms from across the full catalog; verify results appear immediately without requiring prior page loads.
4. Modify one album in Plex (metadata or artwork), refresh, verify only that album updates across grid and detail surfaces.
5. Remove one album in Plex, refresh, verify it disappears locally and associated artwork is pruned.
6. Disconnect network, trigger refresh, verify cached data remains visible and error banner appears.

## Suggested Session Slicing for Future Bots

1. Stage 5I: relationship reconciliation + canonicalization/prune correctness.
2. Stage 5J: flexible filter API and GRDB query planner.
3. Stage 5K: UI adoption of relational filtering.
4. Stage 5L: playlist relational persistence/read APIs.
5. Stage 5M: cleanup + hardening.
6. Stage 6: conditional feasibility instrumentation + diagnostics.
7. Stage 7: conditional integration (only if viability confirmed).

Each session should stay within one module and end with passing tests plus a short QA checklist.

## Out of Scope

- Webhook/event-driven sync.
- New backend services.
- Cross-domain architecture violations.
- Performance tricks unrelated to incremental sync correctness.
