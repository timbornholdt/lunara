# AGENTS.md — Lunara

You are an AI coding agent working on Lunara, a personal iOS music player for a Plex library.

**Before doing anything, read `README.md` in this repo root.** It is the constitution for this project. It defines the architecture, module boundaries, build order, and rules. If your task would violate something in the README, stop and ask the user.

---

## Who You're Working With

The user is the sole developer and architect of this app. They understand software architecture and can read Swift structurally, but they are not a Swift expert and will not catch subtle bugs through code review alone. This means:

- **You are responsible for correctness.** Write unit tests for everything. Don't assume the user will spot logic errors during review.
- **Explain architectural decisions.** When you make a choice (e.g., choosing between `@Observable` vs `ObservableObject`, or how to structure a GRDB migration), briefly explain *why* — one to two sentences is enough. The user wants to learn and steer, not just receive code.
- **Don't explain syntax.** The user doesn't need to know what `async throws` means. Explain the *design* reasoning, not the *language* mechanics.
- **When in doubt about scope or approach:** Propose two to three options with your recommendation and a one-sentence rationale for each. Let the user pick. Do not silently make architectural decisions.

---

## Session Workflow

The user works in quick bursts throughout the day. Sessions are short. Respect this by:

1. **Start every session by stating what you're about to do** in two to three sentences. Don't start writing code without confirming scope. Example: "I'm going to implement the QueueManager protocol we discussed. This session will produce the protocol file and its unit tests. I won't touch PlaybackEngine or any UI."

2. **One module per session.** Even if two things feel related, do one at a time. If the user asks for something that spans modules, propose splitting it into sequential sessions.

3. **End every session with a summary:**
   - What was built or changed (file list).
   - What tests were added and whether they pass.
   - What the user should manually test on device (specific steps, not vague "test playback").
   - What the next logical session would be.

4. **Commit after each coherent unit of work.** Use descriptive commit messages in the format: `[Phase N] Component: what changed`. Example: `[Phase 2] PlaybackEngine: implement AVQueuePlayer with preloading`. The user has authorized you to commit directly.

---

## Architecture Rules (Quick Reference)

These are the critical rules from the README. Burn these in.

### Domain Boundaries
- **Library Domain** and **Music Domain** never import each other.
- Only **AppRouter** and **Shared Types** cross the domain boundary.
- Views send actions through AppRouter. Views observe domain state directly for display.

### Module Communication
| Component | Can talk to | Cannot talk to |
|---|---|---|
| Views | AppRouter (actions), LibraryRepo (read), Music Domain (observe) | PlexAPIClient, LibraryStore, PlaybackEngine (actions) |
| AppRouter | LibraryRepo, QueueManager | PlexAPIClient, LibraryStore, PlaybackEngine directly |
| LibraryRepo | PlexAPIClient, LibraryStore, Artwork Pipeline | Music Domain |
| QueueManager | PlaybackEngine, its own persistence | Library Domain |
| PlaybackEngine | Nothing. It is called and observed. | Everything |
| NowPlayingBridge | PlaybackEngine (observe), QueueManager (observe) | Library Domain |
| AuthManager | Keychain | Everything else |

### Code Quality
- **Files under 300 lines.** If approaching this, split by responsibility before continuing.
- **No singletons.** Dependency injection only. Pass through `init`.
- **No `try?` with silent nil.** Every error either propagates or is explicitly documented with a comment explaining why it's safe to ignore.
- **Every view that shows PlaybackState must handle all five cases:** `idle`, `buffering`, `playing`, `paused`, `error`.
- **Shared types are sacred.** If you need to change a shared type, propose the change and get approval before implementing.
- **Protocol first, implementation second.** Define the interface, present it, get approval, then build.

### What Not to Do
- Don't touch modules outside the current task scope.
- Don't add dependencies or libraries without asking.
- Don't optimize before the basic flow works (no caching tricks, no prefetch strategies, no clever performance hacks unless the task specifically calls for it).
- Don't build anything from a future phase. If the current task would be "easier" with something from a later phase, that's a sign to stop and ask.
- Don't create god objects or manager-of-managers. If a class is doing two things, split it.

---

## Testing Strategy

The user relies on tests for correctness, not code review. This makes your test quality critical.

- **Every module gets unit tests.** No exceptions.
- **Test behavior, not implementation.** Test "when I call `playNow` with 10 tracks, the first track starts playing and `prepareNext` is called with the second track" — not "the internal array has 10 elements."
- **Use protocol-based mocks.** Every module depends on protocols, so inject mock implementations in tests. Don't mock concrete classes.
- **Name tests descriptively.** `test_playNow_withAlbumTracks_startsFirstTrackAndPreloadsSecond` not `testPlayNow`.
- **When you finish writing tests, run them** (if the tool supports it). Report results. If tests fail, fix them before ending the session.
- **Write a manual QA checklist** at the end of each session. Be specific: "1. Open the app. 2. Tap album X. 3. Tap Play. 4. Verify audio starts within 2 seconds. 5. Lock phone. 6. Verify audio continues." The user will run this on a physical iPhone 15 Pro.

---

## File Organization

```
Lunara/
├── App/                          # App entry point, dependency wiring
│   └── LunaraApp.swift
├── Shared/                       # Shared types (both domains use these)
│   ├── Models/
│   │   ├── Album.swift
│   │   ├── Track.swift
│   │   ├── Artist.swift
│   │   ├── Collection.swift
│   │   └── PlaybackState.swift
│   └── Errors/
│       └── LunaraError.swift
├── Library/                      # Library Domain
│   ├── Auth/
│   │   └── AuthManager.swift
│   ├── API/
│   │   └── PlexAPIClient.swift
│   ├── Store/
│   │   └── LibraryStore.swift
│   ├── Repo/
│   │   └── LibraryRepo.swift
│   └── Artwork/
│       └── ArtworkPipeline.swift
├── Music/                        # Music Domain
│   ├── Engine/
│   │   ├── PlaybackEngineProtocol.swift
│   │   └── AVQueuePlayerEngine.swift
│   ├── Queue/
│   │   └── QueueManager.swift
│   ├── NowPlaying/
│   │   └── NowPlayingBridge.swift
│   └── Session/
│       └── AudioSession.swift
├── Router/                       # Coordinator
│   └── AppRouter.swift
├── Views/                        # SwiftUI views
│   ├── Library/
│   ├── Album/
│   ├── Artist/
│   ├── Collection/
│   ├── NowPlaying/
│   ├── Settings/
│   └── Components/               # Shared UI components (error banner, etc.)
└── Resources/                    # Fonts, assets, plists
```

When creating new files, follow this structure. Don't put files in unexpected locations. If a file doesn't clearly fit, ask.

---

## Git Conventions

- **Branch per phase:** `phase-N-description` (e.g., `phase-2-playback-engine-queue`).
- **Commit per coherent unit:** One module, one feature, or one fix per commit. Not one giant commit per session.
- **Commit message format:** `[Phase N] Component: what changed`
- **Don't commit broken code.** If tests fail, fix them first. If something is half-built at the end of a session, stash or note it rather than committing a broken state.

---

## Handling Ambiguity

When you encounter something the README doesn't cover:

1. **Don't guess silently.** The user would rather you pause and ask than build the wrong thing.
2. **Propose two to three options** with a short rationale for each and your recommendation.
3. **Frame options in terms of tradeoffs**, not just technical differences. "Option A is simpler now but will need rework in Phase 7" is more useful than "Option A uses X pattern and Option B uses Y pattern."
4. **If it's a trivial decision** (naming, minor code organization), make it and note it in your session summary. Don't block on things that don't affect architecture.

---

## What Good Output Looks Like

A good session produces:
- A small number of focused files (1-4) that do one thing well.
- Unit tests that cover the main paths and edge cases.
- A brief explanation of any design decisions made.
- A manual QA checklist with specific steps.
- A clean commit with a descriptive message.
- A clear statement of what comes next.

A bad session produces:
- A large number of files touching multiple modules.
- No tests, or tests that only cover the happy path.
- Silent architectural decisions buried in implementation.
- Vague "test that it works" QA instructions.
- Changes to shared types or other modules without flagging them.
