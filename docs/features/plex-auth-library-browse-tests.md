# Test Plan — Plex Auth + Library Browse

## Scope
Unit tests for authentication, API client behavior, model parsing, and UI view-model logic for album browsing with high-quality artwork.

## Requirements → Test Matrix
- Authenticate to a Plex server for a single user.
  - Auth flow returns token on valid credentials.
  - Invalid credentials produce a deterministic error state.
- Persist auth state securely and restore on app launch.
  - Token saved to Keychain on successful login.
  - Token read on launch and attached to client.
  - Invalid/expired token triggers re-auth state.
- Fetch and display albums and their tracks (read-only).
  - Albums list fetch returns expected model list.
  - Album detail fetch returns expected album metadata.
  - Track list fetch returns ordered track list.
- Plex remains source of truth (read-only).
  - Client uses only GET/read endpoints; no writes.
- Include album artwork fetching with highest available quality (capped).
  - Artwork URL generation respects max size cap.
  - Artwork fetch uses token + proper headers.
- Album list pagination (required).
  - Client paginates until totalSize is reached.
  - Client handles empty pages safely.

## Edge Cases
- Multiple music libraries returned; user selection persists in session.
- Empty library or empty album list.
- Album missing artwork path; UI uses placeholder.
- Network error or timeout on albums, tracks, or artwork.
- Token revoked mid-session (401) triggers re-auth and clears cached token.
- Large album list pagination (if Plex API requires it).
  - Multiple pages of albums returned and merged correctly.

## Unit Test Checklist (Approval Required Before Implementation)
- Auth client
  - Token acquisition success
  - Token acquisition failure
  - Token validation success/failure
- Keychain wrapper
  - Save token
  - Read token
  - Delete token
- Plex API client
  - Builds correct URLs for libraries, albums, tracks
  - Builds paginated album list requests
  - Adds required auth headers
  - Parses album list response
  - Merges paginated album list results
  - Parses track list response
  - Builds artwork URL with max size cap
- View models
  - Album list view model loads albums and exposes UI state
  - Album detail view model loads tracks and artwork
  - Error states are surfaced for UI

## Execution Checklist
- Run unit tests in Xcode (all tests pass).
- Validate token persistence by simulating app relaunch (test harness).
- Validate artwork cap logic via URL inspection in tests.

## Open Questions
- None. Max artwork cap set to 2048px. Pagination required in v1.
