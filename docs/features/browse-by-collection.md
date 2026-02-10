# Browse By Collection

## Goal
Add a collections browsing experience alongside the existing all-albums library view, with pinned, highlighted collections and collection-specific album grids.

## Requirements
- The app’s main interface remains the “All Albums” view.
- A bottom tab bar allows switching between “All Albums” and “Collections”.
- Collections list displays album collections (only) with artwork.
- Collections are ordered with `Current Vibes` and `The Key Albums` pinned at the top, and all others sorted alphabetically.
- The two pinned collections are visually distinct via a highlighted card background (subtle, not over-the-top).
- Tapping a collection shows its albums using the same grid style as the main library view.
- Collections are loaded from the first available music library section; no library section selector is shown.
- No third-party dependencies without explicit approval.

## Acceptance Criteria
- A tab bar appears with “All Albums” and “Collections”.
- Collections list shows all album collections for the selected library.
- `Current Vibes` and `The Key Albums` are pinned at the top and visually highlighted.
- Collection detail shows albums in the same grid layout and card style as the main library view.
- Only album collections are shown (no playlists yet).
- A debug log prints the live collection titles after fetch to verify exact naming.

## Constraints
- Use existing SwiftUI + MVVM patterns.
- Use existing Plex networking conventions (request builder + service + paginator).
- Lightweight storage only; no new caching yet.
- Maintain current design system (Lunara theme, linen background).

## Repository Context
- Relevant files:
  - `Lunara/UI/Views/LibraryBrowseView.swift`
  - `Lunara/UI/LibraryViewModel.swift`
  - `Lunara/Plex/Library/PlexLibraryRequestBuilder.swift`
  - `Lunara/Plex/Library/PlexLibraryService.swift`
  - `Lunara/Plex/Library/PlexModels.swift`
  - `Lunara/Plex/PlexProtocols.swift`
- Existing patterns:
  - SwiftUI NavigationStack with MVVM view models.
  - Plex services use request builders and `PlexPaginator`.
  - Album grid is built inside `LibraryBrowseView`.

## Proposed Approach
1. **Plex collections support (library layer)**
   - Add collection models (e.g., `PlexCollection`) in `PlexModels.swift`.
   - Add request builders for collections and for albums in a collection.
   - Extend `PlexLibraryServicing` + `PlexLibraryService` with:
     - `fetchCollections(sectionId:)`
     - `fetchAlbumsInCollection(sectionId:collectionKey:)`
2. **UI structure**
   - Extract a reusable `AlbumGridView` from `LibraryBrowseView`.
   - Create `CollectionsViewModel` to load collections for the selected library section.
   - Create `CollectionAlbumsViewModel` or reuse the same one for collection detail.
   - Introduce a new `CollectionsBrowseView` to list collections.
   - Add a `TabView` at the root of the authenticated flow:
     - Tab 1: `All Albums` (existing library browse)
     - Tab 2: `Collections` (new collections browse)
3. **Pinned + highlighted collections**
   - Use exact title match for `Current Vibes` and `The Key Albums`.
   - Render those two with a subtle highlighted background (e.g., palette accent wash + border).
5. **Debug log (temporary)**
   - After fetching collections, log the raw collection titles to confirm the exact names.
4. **Collection detail**
   - Tapping a collection opens a grid using the extracted `AlbumGridView`.
   - Album detail navigation remains unchanged.

## Alternatives Considered
- **Single monolithic `LibraryViewModel`**: less code, but mixes concerns and reduces test clarity.
- **Single “BrowseMode” view model**: centralized state but higher complexity and more brittle.

## Pseudocode
```
// Models
struct PlexCollection { ratingKey, title, thumb, summary, updatedAt, ... }

// Service
func fetchCollections(sectionId) -> [PlexCollection]
func fetchAlbumsInCollection(sectionId, collectionKey) -> [PlexAlbum]

// ViewModels
class CollectionsViewModel {
  loadCollections(sectionId)
  pinned = ["Current Vibes", "The Key Albums"]
  display = pinnedFirstThenAlphabetical()
  logTitlesForDebug()
}

class CollectionAlbumsViewModel {
  loadAlbums(sectionId, collectionKey)
  albums = dedupe(albums) // reuse existing album dedupe logic if needed
}

// UI
TabView {
  LibraryBrowseView(...)
  CollectionsBrowseView(...)
}

CollectionsBrowseView:
  list/grid collection cards
  pinned cards highlighted background
  tap -> CollectionDetailView(collection)

CollectionDetailView:
  AlbumGridView(albums)
```

## Test Strategy
- Unit tests:
  - Collection request builder builds correct URLs and headers.
  - Collections parsing from Plex response.
  - Pinned ordering: `Current Vibes`, `The Key Albums` at top, others alphabetical.
  - Highlighting flag logic for pinned collections.
  - Albums-in-collection fetch returns expected list and handles pagination.
- Edge cases:
  - No collections.
  - Only one of the pinned collections exists.
  - Collections without artwork.
  - Empty collection.

## Risks / Tradeoffs
- Plex collection endpoints and response shape can vary by server version; may need fallback parsing.
- Extracting `AlbumGridView` requires a small refactor in `LibraryBrowseView`.

## Open Questions
1. None.
