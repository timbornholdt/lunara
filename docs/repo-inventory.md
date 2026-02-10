# Repo Inventory

## Overview
This repo implements Plex auth and read-only library browsing for albums and tracks using a SwiftUI UI and a small Plex networking layer. It is early-stage and focused on Phase 1.1 functionality.

## Code Structure
- App entry: `Lunara/LunaraApp.swift`
- Root view routing: `Lunara/ContentView.swift`
- UI views: `Lunara/UI/Views/`
- UI view models: `Lunara/UI/`
- Plex client + services: `Lunara/Plex/`
- Tests: `LunaraTests/`
- Docs: `README.md`, `docs/`, `docs/features/`

## UI Patterns
- SwiftUI NavigationStack with MVVM-style view models.
- Views are thin; view models handle async loading and error states.
- Album grid (LazyVGrid) with artwork fetched via Plex artwork URLs.
- Album detail view lists tracks (read-only).

## Data/Networking Patterns
- Protocol-first services in `Lunara/Plex/PlexProtocols.swift`.
- Request builders create URLRequests for auth, resources, and library browsing.
- `PlexHTTPClient` handles network calls and status validation.
- Pagination uses `PlexPaginator` and `PlexPage`.
- Server URL and library selection are stored in UserDefaults.
- Auth token is stored in Keychain via `PlexAuthTokenStore`.

## Current Feature Coverage
- Plex PIN auth flow and token validation.
- Server resolution via Plex resources API.
- Library sections fetch and album listing.
- Album detail fetch with track listing.
- Artwork URL generation and display.
- AVPlayer album playback with track-level start and sequential play.
- Global now playing bar with progress and play/pause toggle.

## Tests
- Uses Swift Testing (`import Testing`).
- Unit tests cover auth, request builders, pagination, decoding, and view models.
- Test doubles exist for token storage, server storage, and library service.

## Docs
- `README.md` defines scope, philosophy, and long-term features.
- `docs/project-plan.md` defines phased plan.
- `docs/features/plex-auth-library-browse.md` and tests doc exist.
- Phase 0 docs: `docs/scope-and-non-goals.md`, `docs/product-north-star.md`.

## Gaps vs. Project Plan
- No offline manager or download verification.
- No queue manager or shuffle logic.
- No metadata caching or artwork caching.
- No notes or deletion queue integration.
- No theming system beyond basic artwork display.
- No CarPlay implementation.
- No lock screen/Control Center now playing metadata or remote command handling.
