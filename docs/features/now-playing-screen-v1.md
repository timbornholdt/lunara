# Now Playing Screen v1

## Goal
Deliver a bottom-sheet Now Playing experience with album-level theming, an always-visible Up Next list, interactive scrubbing, and navigation to album detail.

## Requirements
- Tapping the floating Now Playing bar presents the Now Playing screen from the bottom.
- The sheet dismisses via pull-down; the bar fades out while the sheet is visible.
- Screen includes album artwork, album title, album artist, track title, and playback controls.
- Primary controls: Previous, Play/Pause, Next.
- Interactive scrubber: dragging updates timecodes; on release seek to the new time unless within ±5s of current position.
- Up Next list is always visible below controls and shows remaining tracks only (no current or previous tracks).
- Tapping an Up Next track jumps playback to that track.
- Up Next shows track number, title, duration, and artist when it differs from album artist.
- Tapping artwork or album title navigates to the current album detail view (push onto nav stack).
- Theming uses the hierarchy: Personal theme (future) > Era/Genre theme (future) > Artwork-derived theme (v1).
- Theme remains stable for the album (no per-track theming in v1).
- Basic artwork-derived theming is applied to Now Playing and Album Detail screens in v1.
- Text and controls must enforce contrast rules with automatic fallback to neutral colors when needed.

## Acceptance Criteria
- Now Playing sheet presents from any main tab; bar hidden while sheet is visible.
- Pull-down dismiss works from the top of the sheet.
- Scrubber seeks on release, and no-op is respected within ±5s tolerance.
- Up Next list updates as tracks advance, removing played tracks from the list.
- Tapping Up Next jumps to the selected track.
- Album detail opens from Now Playing header/album artwork.
- Artwork-derived theme renders a clean gradient + subtle texture and tints accents in Now Playing and Album Detail.
- Theme fallback maintains minimum contrast for all labels and controls.

## Constraints
- No third-party dependencies.
- SwiftUI-first implementation, aligned with existing MVVM patterns.
- Use existing artwork caching pipeline where possible.

## Repository Context
- /Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/NowPlayingBarView.swift
- /Users/timbornholdt/Repos/Lunara/Lunara/UI/PlaybackViewModel.swift
- /Users/timbornholdt/Repos/Lunara/Lunara/Playback/PlaybackEngine.swift
- /Users/timbornholdt/Repos/Lunara/Lunara/Playback/PlaybackProtocols.swift
- /Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/AlbumDetailView.swift
- /Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/ArtworkView.swift
- /Users/timbornholdt/Repos/Lunara/Lunara/Artwork/ArtworkLoader.swift
- /Users/timbornholdt/Repos/Lunara/docs/ui-brand-guide.md

## Proposed Approach
- Add a `NowPlayingContext` model in the UI layer to carry album metadata and the full track list.
- Extend `NowPlayingState` to include `trackRatingKey` and `albumTitle` or add `NowPlayingMetadata` alongside state.
- Capture context when playback starts from Album Detail:
  - `albumRatingKey`, `albumTitle`, `albumArtist`, `artworkRequest`, `tracks`.
- Present the Now Playing sheet from a shared root container (e.g., `MainTabView`) to avoid duplicated logic across tabs.
- Replace per-view `safeAreaInset` bar with a centralized bar and sheet presenter.
- Implement Up Next from `context.tracks` and the current track’s index using `trackRatingKey`.
- Add playback control APIs:
  - `skipToNext()`
  - `skipToPrevious()`
  - `seek(to seconds: TimeInterval)`
  - `play(tracks:startIndex:)` can be reused for jump-to-track if simpler for v1.
- Implement album-level theming:
  - New `ArtworkThemeExtractor` that generates a palette from a `UIImage` using k-means clustering.
  - Generate a background gradient (dominant + secondary), optional subtle texture overlay.
  - Derive `accentPrimary`, `accentSecondary`, `textPrimary`, `textSecondary` with contrast enforcement.
  - Expose `AlbumTheme` for Now Playing and Album Detail.
- Reuse existing artwork cache via `ArtworkLoader` for palette extraction.

## Alternatives Considered
- Custom bottom sheet with manual drag gestures. Rejected for v1 due to complexity and higher risk.
- Fullscreen cover. Rejected due to mismatch with “sheet from bottom” requirement and UI guide.
- Simple average color extraction. Rejected in favor of k-means palette for a cleaner, “dope” result.

## Pseudocode
```swift
struct NowPlayingContext: Equatable {
    let albumRatingKey: String
    let albumTitle: String
    let albumArtist: String?
    let artworkRequest: ArtworkRequest?
    let tracks: [PlexTrack]
}

struct NowPlayingState: Equatable {
    let trackRatingKey: String
    let trackTitle: String
    let artistName: String?
    let isPlaying: Bool
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
}

final class PlaybackViewModel: ObservableObject {
    @Published private(set) var nowPlaying: NowPlayingState?
    @Published private(set) var nowPlayingContext: NowPlayingContext?
    @Published private(set) var albumTheme: AlbumTheme?

    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
        nowPlayingContext = context
        engine.play(tracks: tracks, startIndex: startIndex)
        if let request = context?.artworkRequest {
            albumTheme = themeProvider.theme(for: request)
        }
    }

    func seek(to seconds: TimeInterval) { engine.seek(to: seconds) }
    func skipToNext() { engine.skipToNext() }
    func skipToPrevious() { engine.skipToPrevious() }
}

struct NowPlayingSheetView: View {
    let state: NowPlayingState
    let context: NowPlayingContext
    let theme: AlbumTheme
    let onSeek: (TimeInterval) -> Void
    let onTapTrack: (PlexTrack) -> Void

    var upNext: [PlexTrack] {
        guard let index = context.tracks.firstIndex(where: { $0.ratingKey == state.trackRatingKey }) else { return [] }
        return Array(context.tracks.dropFirst(index + 1))
    }
}

// Scrubber release behavior
if abs(newTime - state.elapsedTime) > 5 {
   onSeek(newTime)
}
```

## Test Strategy
- Unit tests:
  - Up Next derives from context + current track ID.
  - Tap Up Next triggers `play(tracks:startIndex:)` with selected index.
  - Seek no-op when within ±5s.
  - Theme extractor returns palette and enforces contrast.
  - Theme remains stable for album changes, not track changes.
- UI tests (if available):
  - Bar tap presents sheet; pull-down dismiss restores bar.
  - Tapping artwork navigates to album detail.

## Risks / Tradeoffs
- Exposing queue state from `PlaybackEngine` may require API expansion and careful mapping between indices and track IDs.
- Theme extraction adds CPU cost; must downsample images to keep it fast.
- Color contrast enforcement might flatten some “dope” palettes; we should tune thresholds.

## Open Questions
- None outstanding; requirements confirmed.
```
