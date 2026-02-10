# Lunara Project Plan

## Decisions (Confirmed)
- Phase 1 starts with Plex auth + library browse.
- UI can use UIKit if it simplifies implementation; SwiftUI is optional.
- Local storage should be lightweight (SQLite is acceptable if still standard).
- CarPlay is deferred until core playback and offline are stable.

## Phase 0 — Project Baseline
1. [x] Confirm scope and non-goals
   - Acceptance criteria:
     - README scope and non-goals acknowledged and unchanged.
     - Personal-tool intent recorded in `docs/`.
2. [x] Define product north star
   - Acceptance criteria:
     - 1-sentence product goal.
     - 3 prioritized user outcomes.
3. [x] Inventory current repo
   - Acceptance criteria:
     - Summary of existing code structure, current UI/architecture patterns, and gaps.
4. [x] Define UI design language + brand direction (requirements pending)
   - Product requirements to define:
     - Brand direction: name usage, tone, and visual references.
     - Typography system: primary/secondary fonts and hierarchy rules.
     - Color system: palette, semantic roles, and accessibility targets.
     - Component styling: buttons, lists, cards, navigation, and now playing.
     - Motion rules: transitions and emphasis behavior.
   - Acceptance criteria:
     - A short UI/brand guide is written in `docs/` with examples.
     - At least one core screen is mocked or prototyped to validate the direction.

## Phase 1 — Core Playback Reliability (MVP)
1. [x] Plex API auth + library browse (read-only)
   - Acceptance criteria:
     - Can authenticate to a Plex server.
     - Can fetch albums + tracks metadata.
2. [x] Album de-duplication + track-group merge (library correctness)
   - Acceptance criteria:
     - Albums with identical metadata but split track groups (e.g., single-track vs remainder) are merged into one album view.
     - The merged album exposes the full track list in correct order.
     - No duplicate tiles appear in the library grid.
3. [x] UI assets + sign-in refactor (brand compliance)
   - Acceptance criteria:
     - Playfair Display font asset added to the app and configured in Info.plist.
     - Linen background texture generated on the fly (no static asset), adapts to theme changes.
     - Sign-in screen updated to match `docs/ui-brand-guide.md` (typography, colors, pill buttons, card-style inputs).
4. [x] Playback engine v1 (AVPlayer)
   - Acceptance criteria:
     - Plays a full album sequentially.
     - No truncation on network changes.
5. [ ] Offline manager v1
   - Acceptance criteria:
     - Downloads complete files only.
     - Offline playback skips non-downloaded tracks immediately.
6. [ ] Queue manager v1
   - Acceptance criteria:
     - Play now/next/later works for album insertions.
     - Queue persists across app restarts.
7. [ ] Lock screen now playing + remote controls
   - Acceptance criteria:
     - Lock screen and Control Center show current track, elapsed time, and duration.
     - Play/Pause/Next/Previous remote commands control playback.
8. [ ] Settings screen (sign out + debug logging)
   - Acceptance criteria:
     - Replace the Library "Sign Out" button with a settings gear icon.
     - Settings screen includes Sign Out action.
     - Settings screen includes a toggle to enable album de-dup debug logging.
## Phase 2 — Primary Interaction: Shuffle
1. [ ] Collection shuffle (primary mode)
   - Acceptance criteria:
     - Shuffle obeys anti-annoyance rules.
     - Queue ~500 tracks by default.
2. [ ] Whole-library shuffle
   - Acceptance criteria:
     - Uniform across library with constraints.
3. [ ] Album playback UX
   - Acceptance criteria:
     - Album-first navigation and playback flows are clear and stable.

## Phase 3 — Offline Collections + Storage
1. [ ] Downloaded collections
   - Acceptance criteria:
     - Mark collection as Downloaded triggers sync.
     - Reference counting prevents deletion.
2. [ ] Storage cap + eviction
   - Acceptance criteria:
     - Pinned collections never evict.
     - Unpinned cached audio evicts under pressure.
3. [ ] Caching: artwork + metadata (requirements pending)
   - Product requirements to define:
     - Artwork caching strategy: prefetch during sync vs on-demand + cache.
     - Cache policy: size cap, eviction, and retention rules.
     - Cache separation: artwork vs metadata vs offline audio responsibilities.
   - Acceptance criteria:
     - Album artwork is downloaded and stored locally (per chosen strategy).
     - Artwork cache survives app restarts.
     - Library scroll does not block on live artwork fetch if cached exists.
     - Cache policy is explicitly documented in the product requirements.
4. [ ] Album change detection
   - Acceptance criteria:
     - Changes in Plex trigger re-download on Wi-Fi only.
5. [ ] Selective library sync (metadata caching)
   - Acceptance criteria:
     - Cache library contents locally for fast diffing.
     - Selective sync uses cached index to minimize full refreshes.
     - Sync plans compute adds/removes without re-fetching the full library.

## Future Ideas (Backlog)
- Wikipedia album context (creation/history)
  - Fetch Wikipedia content when an album is loaded.
  - Cache locally with a 1-month expiry.
  - Prioritize content about album creation and recording context.

## Phase 4 — Notes & Deletion Queue
1. [ ] Personal notes
   - Acceptance criteria:
     - Album-tied notes synced to personal server.
2. [ ] Marked for deletion
   - Acceptance criteria:
     - Mark/unmark in app.
     - Auto-clears when Plex no longer has album.

## Phase 5 — Theming + Context
1. [ ] Artwork-derived theming
   - Acceptance criteria:
     - Dominant color, gradient, texture.
     - Does not harm readability.
2. [ ] Era/genre themes
   - Acceptance criteria:
     - Rule-based mapping, subtle UI changes.
3. [ ] Personal memory themes
   - Acceptance criteria:
     - Overrides other theming when present.

## Phase 6 — CarPlay (Deferred)
1. [ ] CarPlay browse + playback
   - Acceptance criteria:
     - Browse collections and albums.
     - Shuffle collection.
     - Now Playing controls.

## First Feature Design Docs (Suggested Order)
1. `docs/features/plex-auth-library-browse.md`
2. `docs/features/avplayer-album-playback.md`
3. `docs/features/offline-manager-v1.md`
4. `docs/features/queue-manager-v1.md`
