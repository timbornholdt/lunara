# AGENTS.md — AppRouter

You are working on the AppRouter (coordinator layer). Read the root `AGENTS.md` and `README.md` if you haven't already.

## Rules
- The AppRouter is the **only** place where Library Domain and Music Domain interact. If you're writing code elsewhere that crosses this boundary, stop — it belongs here.
- No business logic. The router translates user intents: fetch data from LibraryRepo, resolve URLs, hand items to QueueManager. That's it.
- Owns **track URL resolution**: `resolveURL(for:)` checks local files first (when offline is built), falls back to streaming URL. This is where offline/online switching will live.
- If the router file grows beyond ~200 lines, split into sub-routers by concern (e.g., `PlaybackRouter`, `DownloadRouter`).
- The router talks to `LibraryRepo` and `QueueManager`. It does **not** talk to PlexAPIClient, LibraryStore, or PlaybackEngine directly.
