# Lunara Project Plan

## Decisions (Confirmed)
- Phase 1 starts with Plex auth + library browse.
- UI can use UIKit if it simplifies implementation; SwiftUI is optional.
- Local storage should be lightweight (SQLite is acceptable if still standard).
- CarPlay is deferred until core playback and offline are stable.

## Phase 0 — Project Baseline
1. Confirm scope and non-goals
   - Acceptance criteria:
     - README scope and non-goals acknowledged and unchanged.
     - Personal-tool intent recorded in `docs/`.
2. Define product north star
   - Acceptance criteria:
     - 1-sentence product goal.
     - 3 prioritized user outcomes.
3. Inventory current repo
   - Acceptance criteria:
     - Summary of existing code structure, current UI/architecture patterns, and gaps.

## Phase 1 — Core Playback Reliability (MVP)
1. Plex API auth + library browse (read-only)
   - Acceptance criteria:
     - Can authenticate to a Plex server.
     - Can fetch albums + tracks metadata.
2. Playback engine v1 (AVPlayer)
   - Acceptance criteria:
     - Plays a full album sequentially.
     - No truncation on network changes.
3. Offline manager v1
   - Acceptance criteria:
     - Downloads complete files only.
     - Offline playback skips non-downloaded tracks immediately.
4. Queue manager v1
   - Acceptance criteria:
     - Play now/next/later works for album insertions.
     - Queue persists across app restarts.

## Phase 2 — Primary Interaction: Shuffle
1. Collection shuffle (primary mode)
   - Acceptance criteria:
     - Shuffle obeys anti-annoyance rules.
     - Queue ~500 tracks by default.
2. Whole-library shuffle
   - Acceptance criteria:
     - Uniform across library with constraints.
3. Album playback UX
   - Acceptance criteria:
     - Album-first navigation and playback flows are clear and stable.

## Phase 3 — Offline Collections + Storage
1. Downloaded collections
   - Acceptance criteria:
     - Mark collection as Downloaded triggers sync.
     - Reference counting prevents deletion.
2. Storage cap + eviction
   - Acceptance criteria:
     - Pinned collections never evict.
     - Unpinned cached audio evicts under pressure.
3. Album change detection
   - Acceptance criteria:
     - Changes in Plex trigger re-download on Wi-Fi only.

## Phase 4 — Notes & Deletion Queue
1. Personal notes
   - Acceptance criteria:
     - Album-tied notes synced to personal server.
2. Marked for deletion
   - Acceptance criteria:
     - Mark/unmark in app.
     - Auto-clears when Plex no longer has album.

## Phase 5 — Theming + Context
1. Artwork-derived theming
   - Acceptance criteria:
     - Dominant color, gradient, texture.
     - Does not harm readability.
2. Era/genre themes
   - Acceptance criteria:
     - Rule-based mapping, subtle UI changes.
3. Personal memory themes
   - Acceptance criteria:
     - Overrides other theming when present.

## Phase 6 — CarPlay (Deferred)
1. CarPlay browse + playback
   - Acceptance criteria:
     - Browse collections and albums.
     - Shuffle collection.
     - Now Playing controls.

## First Feature Design Docs (Suggested Order)
1. `docs/features/plex-auth-library-browse.md`
2. `docs/features/avplayer-album-playback.md`
3. `docs/features/offline-manager-v1.md`
4. `docs/features/queue-manager-v1.md`
