# Caching: Artwork + Metadata (Phase 1.6)

## Goal
Make browsing feel instant by caching artwork and a lightweight metadata snapshot, while keeping Plex as the source of truth and avoiding heavy sync logic before Phase 1.7.

## Requirements
- Hybrid artwork caching: on-demand fetch with disk persistence plus prefetch of the first screen of results after a library load.
- Artwork cache size cap: 250 MB.
- Eviction policy: LRU by last access.
- Two artwork sizes:
  - 2048px for detail views (high fidelity).
  - 1024px for grid/list usage.
- Lightweight metadata snapshot stored locally for fast initial render on app launch.
- Library refresh shows a visible loading indicator while the live fetch is in progress.

## Acceptance Criteria
- Album and collection artwork is downloaded and stored locally based on the hybrid strategy.
- Artwork cache survives app restarts and is reused on next launch.
- Library scroll does not block on live artwork fetch if cached artwork exists.
- Grid views use 1024px artwork; detail views use 2048px artwork.
- On launch, the library renders immediately from the last snapshot, then refreshes live with a loading indicator.
- Cache policy is explicitly documented in this doc.

## Constraints
- No third-party dependencies without explicit approval.
- Use modern native iOS approaches and repo patterns.
- Keep metadata caching lightweight (no selective sync diffing yet).

## Repository Context
- Relevant files:
  - `Lunara/UI/Views/AlbumGridView.swift`
  - `Lunara/UI/Views/CollectionsBrowseView.swift`
  - `Lunara/UI/LibraryViewModel.swift`
  - `Lunara/Plex/Artwork/PlexArtworkURLBuilder.swift`
- Existing patterns:
  - `AsyncImage` for artwork rendering.
  - View models own async loading and error state.
  - No persistent cache or metadata snapshot yet.

## Proposed Approach
### Artwork caching
- Introduce a small image pipeline:
  - `ArtworkCache` (memory + disk).
  - `ArtworkLoader` that returns cached images or fetches and writes to cache.
- Cache key = `ratingKey + artworkPath + size`.
- Cache storage:
  - Disk in Caches directory, organized by size bucket (`artwork/1024/`, `artwork/2048/`).
  - Memory cache for recently used images (NSCache).
- Eviction:
  - Maintain `lastAccessed` in a small index file (e.g., JSON) per size bucket.
  - On write, prune by LRU until total size <= 250 MB.
- Prefetch:
  - After albums or collections load, prefetch artwork for the first screen (visible rows + one extra row).

### Metadata snapshot
- Store a lightweight snapshot of:
  - Albums list (deduped) and collections list.
  - Minimal fields used by UI for initial render (ratingKey, title, artist, year, thumb/art, etc.).
- Persist snapshot in Application Support after a successful live fetch.
- On app launch:
  - Load snapshot first and render immediately.
  - Then start live refresh; show loading indicator while refreshing.

### UI wiring
- Replace `AsyncImage` with a custom `ArtworkView` that:
  - Asks `ArtworkLoader` for 1024 or 2048 image.
  - Shows placeholder + progress while loading.
  - Uses cached image instantly if present.
- View models expose `isRefreshing` for the library and collections views to drive loading UI.
- Live refresh uses a top progress bar indicator.

## Alternatives Considered
- On-demand only, no prefetch: simpler, but first scroll is still cold.
- Full prefetch on sync: fast browsing but heavy network/storage.
- Core Data metadata cache: heavier than needed for Phase 1.6.

## Pseudocode
```
// ViewModel load flow
if snapshot = snapshotStore.load() {
  albums = snapshot.albums
  collections = snapshot.collections
}
isRefreshing = true
liveAlbums = fetchAlbums()
liveCollections = fetchCollections()
albums = dedupe(liveAlbums)
collections = liveCollections
snapshotStore.save(albums, collections)
isRefreshing = false

// Artwork load flow
key = cacheKey(album, size)
if image = memoryCache.get(key) { return image }
if image = diskCache.get(key) { memoryCache.put(key, image); return image }
image = fetch(url)
diskCache.put(key, image)
memoryCache.put(key, image)
diskCache.evictIfNeededLRU()
return image

// Prefetch
prefetchKeys = visibleItems + nextRowItems
artworkLoader.prefetch(prefetchKeys, size: 1024)
```

## Test Strategy
- Unit tests:
  - Cache key consistency (ratingKey + artworkPath + size).
  - Disk persistence and reload across launches.
  - LRU eviction by last access and size cap enforcement.
  - Metadata snapshot load/save and render-before-refresh flow.
  - Prefetch uses 1024 size and does not block UI.
- Edge cases:
  - Missing artwork paths: use placeholder without errors.
  - Corrupt cache entry: discard and refetch.
  - Snapshot missing or incompatible: fall back to live fetch only.

## Risks / Tradeoffs
- LRU index maintenance adds complexity; keep format simple and robust.
- Two artwork sizes doubles storage needs; size cap must be enforced across both buckets.
- Snapshot may show stale data briefly until refresh completes.

## Open Questions
None.
