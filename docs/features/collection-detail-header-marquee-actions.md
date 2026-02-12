# Collection Detail Header With Marquee + Actions

## Goal
Add a large, collapsing header at the top of collection detail that always uses an animated album-art marquee and includes `Play` and `Shuffle All` actions for the full collection.

## Requirements
- The header appears when a user opens a collection from the Collections tab.
- Header sits at the top of collection detail content and is visually prominent on initial load.
- Header visual is always an animated album-art marquee (no hero-image mode in this version).
- Marquee scrolls left-to-right.
- Marquee content order is randomized each time collection detail is freshly loaded.
- Marquee loops seamlessly in a circular manner (after final album, continue from first with no visible jump).
- When app returns from background to foreground on the same collection screen, marquee resumes without reshuffling.
- Header includes two primary actions:
  - `Play`: queue all tracks from all albums in collection using non-shuffled order.
  - `Shuffle All`: queue all tracks from all albums in collection using shuffled order.
- If the collection has no playable tracks, both actions are disabled.
- Description/summary is out of scope for this pass.
- No analytics instrumentation in this pass.
- Target platform: iOS 26.

## Acceptance Criteria
- Opening a collection from `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/CollectionsBrowseView.swift` shows the new header at the top of `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/CollectionDetailView.swift`.
- Header starts large and collapses as user scrolls down; navigation title fades in as header collapses.
- Marquee visibly moves left-to-right and loops continuously with no terminal stop.
- Marquee ordering is different across separate screen loads and stable during lifecycle resume of same loaded screen.
- `Play` starts playback at track index `0` for the computed non-shuffled queue.
- `Shuffle All` starts playback at track index `0` for a shuffled version of the computed queue.
- When collection resolves to zero tracks, buttons are disabled and no crash/error occurs.
- Existing collection album grid and album navigation behavior remain unchanged below header.

## Constraints
- Follow existing SwiftUI + MVVM patterns in this repo.
- Reuse existing playback orchestration approach used by artist/album detail view models.
- No third-party dependencies.
- Preserve current design language (Lunara typography/palette/linen/theming conventions).

## Repository Context
- Relevant files:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/CollectionDetailView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/CollectionAlbumsViewModel.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/ArtistDetailView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/ArtistDetailViewModel.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/AlbumDetailView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/PlaybackViewModel.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Plex/PlexProtocols.swift`
- Existing patterns:
  - Collection detail currently owns a `CollectionAlbumsViewModel` and renders a grid.
  - Artist detail already implements `Play All` and `Shuffle` via view-model-side track fetch + playback controller calls.
  - Album detail already uses scroll offset preference key + toolbar title fade.

## Proposed Approach
1. **Extend collection detail view model for playback actions**
- Add async methods on `CollectionAlbumsViewModel`:
  - `playCollection(shuffled: Bool)`
  - helper to fetch tracks for all deduped album keys in collection
  - helper to produce `NowPlayingContext` scoped to current collection playback
- Inject a `shuffleProvider` closure (default `.shuffled()`) for deterministic testing.
- Keep error handling consistent with existing unauthorized/session invalidation behavior.

2. **Add marquee model state in collection detail view**
- On initial load success, create a single randomized album sequence used by marquee rendering.
- Keep this randomized order in `@State` so it survives foreground/background and normal state updates.
- Recompute order only when the screen is re-instantiated (new navigation push) or collection changes.

3. **Add reusable marquee hero component**
- New SwiftUI view (for example `CollectionHeroMarqueeView`) that:
  - accepts `[PlexAlbum]` and optional palette
  - duplicates sequence (`base + base`) to support seamless circular looping
  - computes normalized x-offset from elapsed time using `TimelineView(.animation)`
  - moves content left-to-right by translating duplicated track strip and wrapping progress with modulo
- If no artwork exists for an album tile, render fallback raised card placeholder.
- If no albums exist, render static placeholder hero shell with subtle visual texture.

4. **Add collapsing header composition in `CollectionDetailView`**
- Move from flat grid-first layout to:
  - top hero header container (large height at rest)
  - overlay title + button row over marquee with gradient scrim for readability
  - album grid content below
- Track scroll offset via preference key, then:
  - shrink hero height as user scrolls
  - animate toolbar title opacity in similar style to album detail
- Keep now-playing inset and error banners intact.

5. **Button behavior**
- `Play`: call `playCollection(shuffled: false)`
- `Shuffle All`: call `playCollection(shuffled: true)`
- Disable while loading tracks for action, or when no tracks available.

## Alternatives Considered
1. **Horizontal `ScrollView` with programmatic snapping**
- Pros: straightforward to prototype.
- Cons: increased loop-jump risk and less smooth continuous motion.

2. **UIKit carousel bridge (`UICollectionView`)**
- Pros: deep performance controls.
- Cons: unnecessary architecture complexity and style mismatch for this repo.

3. **Static collage fallback**
- Pros: lowest implementation cost.
- Cons: conflicts with approved product direction (animated marquee always).

## Pseudocode
```swift
// CollectionAlbumsViewModel
@Published var marqueeAlbums: [PlexAlbum] = []
@Published var isPreparingPlayback = false

func loadAlbums() async {
  // existing fetch + dedupe logic
  // after albums resolved:
  if marqueeAlbums.isEmpty {
    marqueeAlbums = shuffledForMarquee(albums)
  }
}

func playCollection(shuffled: Bool) async {
  guard isPreparingPlayback == false else { return }
  isPreparingPlayback = true
  defer { isPreparingPlayback = false }

  let serverURL = requireServerURLOrSetError()
  let token = requireTokenOrSetError()
  let service = libraryServiceFactory(serverURL, token)

  // use deduped albums displayed in collection; preserve display order for Play
  let albumKeys = albums.map(\.ratingKey)
  let trackGroups = await fetchTracksPerAlbum(service, albumKeys)
  var tracks = flatten(trackGroups, preservingAlbumOrder: true)

  guard tracks.isEmpty == false else {
    errorMessage = "No tracks found in this collection."
    return
  }

  if shuffled {
    tracks = shuffleProvider(tracks)
  }

  let context = makeNowPlayingContext(
    tracks: tracks,
    albums: albums,
    serverURL: serverURL,
    token: token
  )

  playbackController.play(tracks: tracks, startIndex: 0, context: context)
}
```

```swift
// CollectionDetailView
@State private var scrollOffset: CGFloat = 0
@State private var marqueeSeededAlbums: [PlexAlbum] = []

var body: some View {
  ScrollView {
    ScrollOffsetReader()

    VStack(spacing: 0) {
      CollapsingHeader(
        height: headerHeight(for: scrollOffset),
        content: {
          CollectionHeroMarqueeView(albums: marqueeSeededAlbums)
          HeaderScrimOverlay()
          HeaderTitleAndButtons(
            title: collection.title,
            onPlay: { Task { await viewModel.playCollection(shuffled: false) } },
            onShuffle: { Task { await viewModel.playCollection(shuffled: true) } },
            buttonsEnabled: viewModel.hasPlayableTracks
          )
        }
      )

      AlbumGridSection(albums: viewModel.albums)
    }
  }
  .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
  .toolbarTitleOpacity(navTitleOpacity(for: scrollOffset))
  .task {
    await viewModel.loadAlbums()
    if marqueeSeededAlbums.isEmpty {
      marqueeSeededAlbums = viewModel.marqueeAlbums
    }
  }
}
```

```swift
// CollectionHeroMarqueeView
TimelineView(.animation) { context in
  let progress = normalizedProgress(date: context.date, speed: pointsPerSecond)
  let baseWidth = tileWidth * CGFloat(baseAlbums.count)
  let wrappedOffset = progress * baseWidth

  HStack(spacing: tileSpacing) {
    ForEach(duplicatedAlbums) { album in
      MarqueeAlbumTile(album: album)
    }
  }
  // left-to-right movement
  .offset(x: -baseWidth + wrappedOffset)
  .clipped()
}
```

## Test Strategy
- Unit tests (`CollectionAlbumsViewModel`):
  - `playCollection(shuffled: false)` requests tracks for all album keys and preserves deterministic non-shuffled order.
  - `playCollection(shuffled: true)` applies injected `shuffleProvider` output.
  - Empty-track result sets actionable error and does not call playback.
  - Missing token/server URL handling remains consistent.
  - Unauthorized errors clear token and trigger session invalidation callback.
- Unit tests (marquee state prep logic):
  - Marquee ordering seeds once per load and is not regenerated by non-load updates.
  - Randomization helper returns permutation with same members.
- View behavior tests (if current harness supports):
  - Header action buttons disabled when no playable tracks.
  - Collapsing threshold math returns expected title opacity/height values for key offsets.
- Manual QA:
  - Enter collection detail multiple times and verify different marquee order each screen load.
  - Background/foreground app and verify marquee resumes without reshuffle.
  - Validate seamless loop continuity visually.
  - Confirm `Play` and `Shuffle All` produce expected queue behavior.

## Risks / Tradeoffs
- Continuous animation over many artwork tiles can increase GPU usage on older devices; iOS 26 target reduces risk but should still be profiled.
- Track-fetch fanout for large collections may increase latency before playback starts.
  - Mitigation: parallelized track fetch with bounded task groups and loading state.
- Seamless looping math can cause subtle jitter if tile widths differ.
  - Mitigation: fixed tile sizing in marquee.

## Open Questions
- None for this scoped version.
