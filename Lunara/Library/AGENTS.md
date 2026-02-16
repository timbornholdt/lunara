# AGENTS.md — Library Domain

You are working inside the Library Domain. Read the root `AGENTS.md` and `README.md` if you haven't already.

## Boundary Rules
- This domain owns: PlexAPIClient, AuthManager, LibraryStore (GRDB), LibraryRepo, Artwork Pipeline.
- This domain **never imports anything from the Music domain** (`Music/` directory). If you need playback state or queue information, that's a sign you're crossing boundaries — stop and ask.
- The public API surface is `LibraryRepo`. External consumers (Views, AppRouter) talk to LibraryRepo, not to PlexAPIClient or LibraryStore directly.
- Shared types from `Shared/` are fine to import and use.

## Storage
- All persistence uses GRDB with a single SQLite database.
- GRDB record types (structs conforming to `FetchableRecord`, `PersistableRecord`) live here, not in `Shared/`. Shared types are plain structs; this domain maps between them and GRDB records internally.
- Artwork files are stored on disk. LibraryStore tracks file paths only.

## Error Handling
- All errors are typed as `LibraryError` (conforms to `LunaraError`).
- Network failures during refresh must surface to the UI but never destroy cached data. The app must remain usable with stale data.

## Auth
- Plex token lives in Keychain, managed by AuthManager.
- PlexAPIClient calls `AuthManager.validToken()` before every request. It never stores or manages the token itself.
