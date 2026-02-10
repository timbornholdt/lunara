# Artist Detail Screen v1

## Goal
Add an Artists tab with a fast, searchable artist list and a rich artist detail screen that includes biography, albums, and artist-level playback actions.

## Requirements
- Add a new `Artists` tab.
- Artist list is alphabetical by `titleSort` when available, otherwise by name.
- Local search filters the in-memory list (no API search).
- Artist list rows are text-only (no thumbnails).
- Artist detail uses a hero image; if artist artwork is missing, use a neutral linen block.
- Use Plex artist summary as the bio; show truncated text with inline expand/collapse.
- Artist detail shows any useful metadata available from the Plex artist payload, including country with emoji flag when a reliable ISO code is available.
- Artist detail shows genres as pills.
- Artist detail shows albums in a single-column list with album art thumbnails, title, year, runtime, and user star rating if present.
- Album list merges albums where the artist appears on another release (ex: compilations) into the same list.
- Artist albums are sorted by release year ascending.
- Tapping an album navigates to `AlbumDetailView`.
- Artist detail includes `Play All` and `Shuffle` actions.
- Now Playing should reflect the current track's album and should navigate to that album.
- Use neutral linen background (no album-derived theming).
- Extend caching to include artists list.
- Validate Plex artist endpoints and country code availability early.

## Acceptance Criteria
- Tab order is `Collections`, `All Albums`, `Artists`.
- Artists tab renders quickly from cached snapshot if available, then refreshes live.
- Search filters artists locally with no server calls.
- Selecting an artist opens detail with hero art, expandable bio, metadata, genre pills, and album list.
- Album list includes user rating when present; runtimes are shown when available or computed from album tracks for appears-on entries.
- Albums that only appear via artist track associations are included in the main list.
- `Play All` queues all artist tracks in album order; `Shuffle` queues artist tracks in random order.
- Now Playing album art navigation always goes to the currently playing track's album.

## Constraints
- No third-party dependencies.
- Use existing MVVM patterns and service architecture.

## Repository Context
- Relevant files:
  - `Lunara/ContentView.swift`
  - `Lunara/UI/Views/LibraryBrowseView.swift`
  - `Lunara/UI/Views/CollectionsBrowseView.swift`
  - `Lunara/UI/Views/AlbumDetailView.swift`
  - `Lunara/UI/AlbumDetailViewModel.swift`
  - `Lunara/UI/PlaybackViewModel.swift`
  - `Lunara/Plex/Library/PlexLibraryService.swift`
  - `Lunara/Plex/Library/PlexLibraryRequestBuilder.swift`
  - `Lunara/Plex/Library/PlexModels.swift`
  - `Lunara/LibrarySnapshot/LibrarySnapshotStore.swift`
- Existing patterns:
  - MVVM with SwiftUI `@StateObject` view models.
  - Plex service factory injected into view models.
  - Snapshot caching for albums and collections.
  - Artwork loading via `ArtworkRequestBuilder` and `ArtworkView`.

## Proposed Approach
### Data models
- Add `PlexArtist` model with fields needed for list + detail:
  - `ratingKey`, `title`, `titleSort`, `summary`, `thumb`, `art`, `country`, `genres`, `userRating`, `rating`, `albumCount`, `trackCount`, `addedAt`, `updatedAt`.
- Add `PlexArtist` decoding using Plex artist payload keys.

### Plex endpoints (validate early)
- Artist list: prefer `GET /library/sections/{sectionId}/artists`.
- Artist detail: `GET /library/metadata/{artistRatingKey}`.
- Artist albums: `GET /library/metadata/{artistRatingKey}/children` (expecting album items).
- Artist tracks for playback:
  - Prefer `GET /library/metadata/{artistRatingKey}/allLeaves` if available.
  - Otherwise, gather tracks via album list (only for playback, not for runtime).
- Country code availability: confirm whether Plex returns ISO codes or only names; only render emoji if ISO code is present.

### Service layer
- Extend `PlexLibraryRequestBuilder` with artist requests.
- Extend `PlexLibraryServicing` and `PlexLibraryService` with:
  - `fetchArtists(sectionId:)`
  - `fetchArtistDetail(artistRatingKey:)`
  - `fetchArtistAlbums(artistRatingKey:)`
  - `fetchArtistTracks(artistRatingKey:)`

### Caching
- Extend `LibrarySnapshot` to include cached artists (ratingKey, title, titleSort, thumb, art).
- Store artist list snapshot and render immediately on Artists tab if present.

### UI
- `ArtistsBrowseView` with:
  - Search field at top.
  - List of artist names (text-only rows).
  - Navigation to `ArtistDetailView`.
- `ArtistDetailView` with:
  - Hero image (artist art), fallback to linen block.
  - Name, inline bio with expand/collapse.
  - Metadata row(s) including country flag when ISO code available.
  - Genres as pill components (shared with album detail later).
  - `Play All` and `Shuffle` buttons side by side with icons.
- Album list (single column) with thumbnail + year + runtime (if available) + user rating.
  - If runtime is missing on appears-on albums, compute from the album tracks.

### Playback
- `Play All`:
  - Fetch artist tracks (preferred single endpoint).
  - Sort by album year ascending, then track order.
- `Shuffle`:
  - Fetch artist tracks and randomize order.
- Now Playing context remains album-based and should navigate to the currently playing track's album.

## Alternatives Considered
- Derive artists from album list instead of Plex artist endpoint.
  - Rejected: loses artist summaries, art, and metadata.
- Per-album track fetch to compute runtime.
  - Rejected for v1 due to performance cost.
- Artist list with thumbnails.
  - Rejected per requirement.

## Pseudocode
```
ArtistsViewModel.loadArtists():
  if snapshot exists: artists = snapshot.artists
  fetch artists from Plex
  sort by titleSort/name
  save snapshot

ArtistsBrowseView:
  TextField(searchQuery)
  List(filteredArtists) { artist in
    NavigationLink -> ArtistDetailView(artist.ratingKey)
  }

ArtistDetailViewModel.load():
  fetch artist detail (summary, art, country, genres)
  fetch artist albums
  sort albums by year ascending

ArtistDetailView.playAll():
  tracks = fetchArtistTracks(artistKey)
  tracks = sortTracksByAlbumYearThenIndex(tracks, albums)
  playback.play(tracks, startIndex: 0, context: nowPlayingContextForAlbumOfFirstTrack)

ArtistDetailView.shuffle():
  tracks = fetchArtistTracks(artistKey)
  tracks.shuffle()
  playback.play(tracks, startIndex: 0, context: nowPlayingContextForAlbumOfFirstTrack)
```

## Test Strategy
- Unit tests:
  - Decoding `PlexArtist` for list and detail payloads.
  - Request builder URLs for artist endpoints.
  - Sorting artists by `titleSort` then name.
  - Local search filtering.
  - Album list sorting by year ascending with nil year handling.
  - `Play All` track ordering and `Shuffle` randomization (deterministic with seeded RNG in tests).
  - Snapshot caching for artist list.
- Edge cases:
  - Missing artist art -> linen fallback.
  - Missing summary -> hide bio block.
  - Missing country code -> omit emoji flag.
  - Empty artist albums -> show empty state copy.

## Risks / Tradeoffs
- Plex endpoint variance for artists; validate early.
- Artist track fetch endpoint may differ across server versions.
- Playback context is album-based; artist-level context deferred.
- Runtime display omitted unless available from initial fetch.

## Open Questions
- Confirm Plex artist endpoint behavior and payload fields in the target server.
- Confirm if artist track endpoint is stable across Plex versions.
