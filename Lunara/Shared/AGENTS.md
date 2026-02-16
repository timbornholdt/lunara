# AGENTS.md — Shared Types

You are working inside the Shared Types layer. Read the root `AGENTS.md` and `README.md` if you haven't already.

## Rules
- **Shared types are sacred.** Changes here affect both domains and all views. Do not modify existing shared types without explicit user approval.
- Structs and enums only. No classes. No protocols (except `LunaraError`). No logic beyond computed properties.
- No GRDB conformances. No UIKit/SwiftUI imports. No domain-specific logic.
- If you're tempted to add a method that calls a service or performs I/O, it belongs in a domain, not here.
- `PlaybackState` must always include: `idle`, `buffering`, `playing`, `paused`, `error(String)`. Do not remove or rename cases without discussing impact on every view that handles playback state.
