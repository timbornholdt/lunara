# Lunara Project Plan

## Decisions (Confirmed)
- Phase 1 starts with Plex auth + library browse.
- UI can use UIKit if it simplifies implementation; SwiftUI is optional.
- Local storage should be lightweight (SQLite is acceptable if still standard).
- CarPlay is deferred until core playback and offline are stable.
- Phase 1 is complete and the next active initiative is a phased full rewrite of playback/offline/library architecture.
- Rewrite delivery constraints:
  - New `codex/...` branch per phase.
  - Stop after each phase for explicit user approval.
  - Provide manual device QA checklist per phase (iPhone 15 Pro, iOS 26.2).
  - Agent runs unit tests; user focuses on manual validation.

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
5. [x] Browse by collection
   - Progress update (2026-02-12):
     - Added collection detail hero refresh: a large collapsing marquee header with Play and Shuffle All actions, including collection-wide queue orchestration and unit coverage for playback + marquee/collapse math.
   - Acceptance criteria:
     - App's main interface is the "all albums" interface, but a tab bar at the bottom allows me to browse by Plex album collections.
     - The main collections view shows all Plex album collections, including the artwork associated with them. Current Vibes and The Key Albums are always at the top, all others are below it alphabetically. Those two are also visually distinct.
     - Clicking a collection shows the albums in that collection in the same manner as the main library view.
6. [x] Caching: artwork + metadata (requirements defined in `docs/features/caching-artwork-metadata.md`)
   - Requirements summary:
     - Hybrid artwork caching with first-screen prefetch.
     - 250 MB cache cap, LRU eviction by last access.
     - Dual artwork sizes: 2048 (detail), 1024 (grid).
     - Lightweight metadata snapshot for fast initial render.
     - Loading indicator during live refresh.
   - Acceptance criteria:
     - Album artwork is downloaded and stored locally (per chosen strategy).
     - Artwork cache survives app restarts.
     - Library scroll does not block on live artwork fetch if cached exists.
     - On launch, cached metadata renders immediately, then refreshes live with a loading indicator.
     - Selective sync uses cached index to minimize full refreshes.
     - Sync plans compute adds/removes without re-fetching the full library.
7. [x] Initial screen
   - Acceptance criteria:
     - When the app loads, it should show an image of some sort along with the text "Lunara" and a loading indicator
	 - The app should check if the token is still valid or if the user is not signed in. If the user is valid, move right into the library view.
	 - Otherwise, show the login screen.
8. [x] Now playing screen v1
   - Acceptance criteria:
     - Work with the user to define what should be present on a now playing screen
	 - Tapping the floating "now playing" bar should bring the "now playing" screen up from the bottom. You should be able to pull down from the top of that screen to dismiss it at any time. The now playing bar should fade out when this screen is present and reappear when it is dismissed.
9. [x] Artist detail screen v1
   - Acceptance criteria:
     - New tab called "Artists" with local search; tab order is Collections, All Albums, Artists.
     - Artist list is alphabetical (uses `titleSort` when available) and text-only rows.
     - Artist detail shows hero art with linen fallback, expandable Plex summary, and genre pills.
     - Artist detail includes Play All and Shuffle actions.
     - Album list is single-column with thumbnails, year, user rating when present, and runtime only if available from initial fetch.
     - Albums sorted by release year ascending.
     - Tapping an album loads that album's page.
10. [x] Settings screen (sign out + debug logging)
   - Requirements defined in `docs/features/settings-screen-v1.md`
   - Requirements summary:
     - Replace top-right Sign Out actions with a shared settings gear entry point.
     - Settings includes Sign Out and an album de-dup debug logging toggle.
     - De-dup debug logging preference is persisted and gates logging output at runtime.
     - Settings structure is extensible for future A/B experiment toggles.
   - Acceptance criteria:
     - Replace the Library "Sign Out" button with a settings gear icon.
     - Settings screen includes Sign Out action.
     - Settings screen includes a toggle to enable album de-dup debug logging.
11. [x] Offline manager v1
   - Requirements defined in `docs/features/offline-manager-v1.md`
   - Progress update (2026-02-11):
     - Implemented Wi-Fi-only offline download queue, local-first playback integration, opportunistic current+next-5 caching hooks, manage downloads screen, collection reconciliation on refresh, 120 GB eviction with non-explicit LRU policy, and sign-out offline purge.
     - Remaining polish: verify final UX/error messaging details during manual QA.
   - Acceptance criteria:
     - A user can tap a "download" button on the "show album" page that triggers a download of all tracks on that album
	 - A user can also download a "collection", which will download all albums from that collection
	 	- If an album within a collection is already downloaded, it will not download it again
	 - The settings screen will have a "Manage downloads" section where I can see all downloaded albums and collections
	   - I should also see a progress indicator of the tracks that are downloading at the moment
     - Must download complete files only. If a track cannot finish downloading, it will be removed from downloads.
     - Offline playback skips non-downloaded tracks immediately.
	 - When an album is played and a stream of the song is started, each complete stream should be saved for offline playback later
	 - The playback tool checks the local cache of songs first before reaching out to download it.
12. [x] Queue manager v1
   - Requirements defined in `docs/features/queue-manager-v1.md`
   - Progress update (2026-02-12):
     - Confirmed v1 behavior: separate QueueManager, default rollout (no feature flag), persisted queue+elapsed+play/pause (restore paused), play now/next/later insertion semantics, partial inserts with detailed skipped-reason banners, duplicate-insert burst protection, and queue clear/remove UX in Now Playing.
   - Status update (2026-02-12):
     - Implemented and validated with full unit test pass.
   - Acceptance criteria:
     - Play now/next/later works for album insertions.
	   - Play Now removes all items from the queue and beings playing the album from track 1
	   - Play next preserves the existing queue and inserts all tracks from the album to the top of the queue
	   - Play later preserves the existing queue and inserts all tracks from the album to the bottom of the queue
     - Queue persists across app restarts.
	 - Long pressing on an individual track opens a menu which allows me to add the track in the same manner as the albums described above
13. [x] Lock screen now playing + remote controls
   - Requirements defined in `docs/features/lock-screen-now-playing-remote-controls.md`
   - Status update (2026-02-12):
     - Activated as current work item after deferring 1.12.
     - Scope confirmed to include lock-screen artwork in this pass.
   - Progress update (2026-02-12):
     - Implemented Lock Screen/Control Center now playing metadata (including artwork when available) plus Play/Pause/Next/Previous remote command support with protocol-backed adapters and unit coverage.
   - Acceptance criteria:
     - Lock screen and Control Center show current track, elapsed time, and duration.
     - Lock screen and Control Center show artwork when available.
     - Play/Pause/Next/Previous remote commands control playback.


## Phase 2 — Playback Architecture Rewrite (Active)
Reference: `docs/features/playback-rewrite-phased-cutover-plan.md`

1. [ ] P0 diagnostics baseline
   - Acceptance criteria:
     - JSONL diagnostics file is written locally with playback/navigation lifecycle events.
     - Baseline metrics captured: startup-to-first-audio, skip-to-audio, skip-to-ui-sync.
2. [ ] P1 playback domain single-source-of-truth
   - Acceptance criteria:
     - Queue progression, current item, and playback state are owned by one concurrency-isolated domain.
     - Audible playback and now-playing UI remain synchronized during rapid skip operations.
3. [ ] P2 durable queue + relaunch semantics
   - Acceptance criteria:
     - Queue and elapsed position persist across force quit and relaunch.
     - Relaunch restores state but waits for explicit Play.
     - Missing local item skips to next available item.
4. [ ] P3 offline download engine rewrite
   - Acceptance criteria:
     - Stream-oriented downloads replace full-memory buffering.
     - Local-first source resolution remains low-latency under queue load.
     - Predictive prefetch of next 3 tracks is active.
     - Cache cap is enforced at 128 GB with dynamic eviction.
5. [ ] P4 library repository rewrite (disk-first + manual refresh)
   - Acceptance criteria:
     - Collection/album/artist/detail navigation reuses disk cache on back navigation.
     - Plex refresh occurs only via explicit pull-to-refresh.
6. [ ] P5 background/remote hardening
   - Acceptance criteria:
     - Lock-screen and Control Center metadata is consistent through lifecycle transitions.
     - Play/Pause/Next/Previous remote commands are stable.
7. [ ] P6 performance and regression sweep
   - Acceptance criteria:
     - Metrics improve over P0 baseline.
     - Manual regression sweep passes for playback, downloads, and navigation.
8. [ ] FF1 gapless/crossfade foundation
   - Acceptance criteria:
     - Transition scaffolding is integrated without core playback regressions.
     - Diagnostics markers exist for transition decision paths.

## Phase 3 — Primary Interaction: Shuffle
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

## Phase 4 — Offline Collections + Storage
1. [ ] Downloaded collections
   - Acceptance criteria:
     - Mark collection as Downloaded triggers sync.
     - Reference counting prevents deletion.
2. [ ] Storage cap + eviction
   - Acceptance criteria:
     - Pinned collections never evict.
     - Unpinned cached audio evicts under pressure.
3. [ ] Album change detection
   - Acceptance criteria:
     - Changes in Plex trigger re-download on Wi-Fi only.

## Phase 5 — Deep linking
1. Boot from the side button on the iPhone 15 Pro
  - Pushing that button starts playing a random album as fast as possible (loads the "now playing" screen)

## Phase 6 — Notes & Deletion Queue
1. [ ] Personal notes
   - Acceptance criteria:
     - Album-tied notes synced to personal server.
2. [ ] Marked for deletion
   - Acceptance criteria:
     - Mark/unmark in app.
     - Auto-clears when Plex no longer has album.

## Phase 7 — Theming + Context
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

## Phase 8 — CarPlay
1. [ ] CarPlay browse + playback
   - Acceptance criteria:
     - Browse collections and albums.
     - Shuffle collection.
     - Now Playing controls.

## Backlog
- Wikipedia album context (creation/history)
  - Fetch Wikipedia content when an album is loaded.
  - Cache locally with a 1-month expiry.
  - Prioritize content about album creation and recording context.
- Convert album detail genre list to pill UI (share component with artist genres).
- Playlist support (collections view extension)
  - Add playlist browsing alongside collections.
  - Support playlist playback and queue integration.
- Digital gardening tool (maybe we can call it The Weeder)
  - An album or track or collection or artist can have a "todo" gardening action
  - From the now playing screen, I can tap a garden-esque icon (a plant or something) that brings up a pop up text box
  - The text box allows me to type in something (e.g. "fix album art")
  - On the settings page, I see a page that lets me browse these todos. Tapping a todo shows me enough detail (e.g. the track title, artist name, collection name, album name, whatever context is appropriate) and the note I made. I can mark the task as complete.
- Dope ass loading indicator
  - Have the AI make a few that i can switch and review in app using feature flags and on the settings page
- Make the colors in the tab bar change when you are on an album view (the default blue looks like shit)
  
## First Feature Design Docs (Suggested Order)
1. `docs/features/plex-auth-library-browse.md`
2. `docs/features/avplayer-album-playback.md`
3. `docs/features/offline-manager-v1.md`
4. `docs/features/queue-manager-v1.md`
