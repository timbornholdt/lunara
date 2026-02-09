# Plex Auth + Library Browse

## Goal
Enable secure authentication to a single Plex server and provide read-only browsing of albums and tracks to establish the core data access patterns for the app.

## Requirements
- Authenticate to a Plex server for a single user.
- Persist auth state securely and restore on app launch.
- Fetch and display albums and their tracks (read-only).
- Plex remains the source of truth for metadata.
- Include album artwork fetching with highest available quality.

## Acceptance Criteria
- User can sign in and establish a valid Plex session.
- App can list albums and view album details (including tracks).
- App survives relaunch without re-authentication (unless token invalid).
- No metadata is modified in this feature.

## Constraints
- No third-party dependencies without explicit approval.
- Use modern native iOS approaches; UIKit is acceptable.
- Use lightweight local storage (SQLite acceptable if needed).
- API-only for this phase (no local caching).

## Repository Context
- Relevant files: TBD (no existing implementation found yet).
- Existing patterns: TBD after code scan.

## Proposed Approach
1. Implement a Plex API client module with minimal endpoints:
   - Auth token acquisition
   - Library sections / music libraries
   - Album list + album details + tracks
   - Album artwork fetch (prefer highest quality available)
2. Create an auth flow that stores the Plex token in Keychain.
3. Build a basic browsing UI:
   - Music library selection (if multiple)
   - Album list
   - Album detail with track list
4. Implement a polished browse UI (visual album grid/list with artwork).

## Alternatives Considered
- Skip local caching and rely purely on live API calls. Simpler, but slower and no offline list view. (Chosen for this phase)
- Use Core Data for metadata caching. More structure, but heavier than needed at this stage.

## Pseudocode
```
// Auth
if keychain.hasToken() {
  client.token = keychain.token
  if !client.validateToken() { promptSignIn() }
} else {
  promptSignIn()
}

// Browse
libraries = client.fetchMusicLibraries()
selectedLibrary = userPick(libraries)
albums = client.fetchAlbums(libraryId)
artwork = client.fetchAlbumArt(albumIds, quality: .highest)

// Album detail
album = client.fetchAlbum(albumId)
tracks = client.fetchTracks(albumId)

// UI
AlbumGridView(albums, artwork)
AlbumDetailView(album, tracks, artwork)
```

## Test Strategy
- Unit tests:
  - Plex client builds correct request URLs and headers.
  - Token storage and retrieval from Keychain.
  - Parsing of album and track models from Plex responses.
- Edge cases:
  - Expired/invalid token triggers re-auth flow.
  - Multiple music libraries present.
  - Empty library or album with missing metadata.

## Risks / Tradeoffs
- Plex auth flow specifics may require WebView or device PIN flow; implementation details need confirmation.
- API schema variations between Plex server versions.
- High-quality artwork fetching may impact performance; consider caching later.

## Open Questions
1. Max artwork size cap: 2048px. (Confirmed)
