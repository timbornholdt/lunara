# Lock Screen Now Playing + Remote Controls (Phase 1.13)

## Goal
Expose current playback on iOS Lock Screen and Control Center, and support Play/Pause/Next/Previous hardware/remote commands using the existing playback pipeline.

## Requirements
- Lock Screen and Control Center show current track metadata.
- Display elapsed time and total duration when available.
- Display track/album artwork on Lock Screen and Control Center when artwork is available.
- Remote commands support:
  - Play/Pause
  - Next track
  - Previous track
- Behavior remains aligned with existing `PlaybackViewModel` + `PlaybackEngine` architecture.
- No third-party dependencies.

## Acceptance Criteria
- While audio is active, Lock Screen/Control Center display:
  - track title
  - artist
  - elapsed time
  - duration (when known)
  - artwork (when available, with graceful fallback when unavailable)
- Remote Play/Pause/Next/Previous commands trigger the same behavior as in-app controls.
- Metadata updates as tracks advance and progress changes.
- Metadata/remote command handlers are cleared when playback stops or user signs out.

## Constraints
- Keep `PlaybackEngine` focused on playback state and queue behavior (no direct MediaPlayer coupling).
- Use native Apple frameworks only (`MediaPlayer`).
- Preserve polished user-facing error behavior already in place.

## Repository Context
- Relevant files:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/PlaybackViewModel.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Playback/PlaybackEngine.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Playback/PlaybackProtocols.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/ContentView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Info.plist`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/Playback/PlaybackViewModelTests.swift`
  - `/Users/timbornholdt/Repos/Lunara/LunaraTests/Playback/PlaybackEngineTests.swift`
- Existing patterns:
  - `PlaybackEngine` publishes `NowPlayingState`.
  - `PlaybackViewModel` is the orchestration layer for playback, context, and side effects.
  - Audio background mode (`UIBackgroundModes: audio`) is already enabled.

## Options Considered
### Option A: Add Lock Screen integration at `PlaybackViewModel` layer (Recommended)
- Introduce two wrappers:
  - `NowPlayingInfoCenterUpdating` for `MPNowPlayingInfoCenter`.
  - `RemoteCommandCenterHandling` for `MPRemoteCommandCenter`.
- `PlaybackViewModel` binds to these wrappers, updating metadata from `NowPlayingState` and wiring command callbacks to existing methods.
- Pros:
  - Keeps `PlaybackEngine` platform-agnostic and test-friendly.
  - Reuses existing view-model orchestration seam and test style.
  - Easy unit testing with protocol test doubles.
- Cons:
  - Adds a small amount of glue code in the view model.

### Option B: Integrate directly in `PlaybackEngine`
- Pros:
  - Centralized near playback state production.
- Cons:
  - Couples engine to iOS MediaPlayer APIs.
  - Harder to test and conflicts with existing separation of concerns.
  - Engine lacks album/context-level metadata owned by the view model.

### Option C: Integrate in SwiftUI views (`ContentView` / Now Playing UI)
- Pros:
  - Fast to wire from currently visible UI state.
- Cons:
  - Risks lifecycle bugs when views appear/disappear.
  - Wrong ownership for background command handling.

## Decision
Adopt Option A.

Rationale:
- Best fit with current architecture and testing approach.
- Minimal risk to core playback logic.
- Cleanly supports lock-screen updates even when UI hierarchy changes.

## Proposed Approach
1. Add MediaPlayer adapter protocols
- In playback domain (or nearby infra), add:
  - `NowPlayingInfoCenterUpdating`
    - `update(with metadata: LockScreenNowPlayingMetadata)`
    - `clear()`
  - `RemoteCommandCenterHandling`
    - `configure(handlers: RemoteCommandHandlers)`
    - `teardown()`
- Add concrete implementations using `MPNowPlayingInfoCenter.default()` and `MPRemoteCommandCenter.shared()`.

2. Add lock-screen metadata model
- Create `LockScreenNowPlayingMetadata` containing:
  - title
  - artist
  - albumTitle
  - elapsedTime
  - duration
  - isPlaying
  - artwork image (`UIImage?`)
- Build metadata from `NowPlayingState` + `NowPlayingContext`.

3. Wire in `PlaybackViewModel`
- Inject both adapters (defaults to real implementations; tests use stubs).
- On every playback state change:
  - map state/context to lock-screen metadata
  - send to info center updater
- On album/context changes:
  - resolve artwork via existing artwork pipeline
  - update lock-screen metadata with resolved image
- On `stop()`:
  - clear metadata
  - tear down remote command handlers
- On first active playback setup:
  - configure remote command handlers:
    - play -> `togglePlayPause()` only when currently paused
    - pause -> `togglePlayPause()` only when currently playing
    - next -> `skipToNext()`
    - previous -> `skipToPrevious()`

4. Lifecycle safeguards
- Ensure command targets are registered once per view-model lifecycle.
- Ensure teardown runs on stop/sign-out flow (`playbackViewModel.stop()` already called in sign-out closure).

5. Artwork integration (in-scope for this pass)
- Add `LockScreenArtworkProviding` adapter:
  - Input: `ArtworkRequest?`
  - Output: `UIImage?`
- Prefer existing cache-backed artwork loading path.
- Include `MPMediaItemPropertyArtwork` when image resolution succeeds.
- Clear artwork when playback/context is cleared to avoid stale lock-screen art.

## Pseudocode
```swift
struct LockScreenNowPlayingMetadata {
    let title: String
    let artist: String?
    let albumTitle: String?
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
    let isPlaying: Bool
    let artworkImage: UIImage?
}

protocol NowPlayingInfoCenterUpdating {
    func update(with metadata: LockScreenNowPlayingMetadata)
    func clear()
}

struct RemoteCommandHandlers {
    let onPlay: () -> Void
    let onPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
}

protocol RemoteCommandCenterHandling {
    func configure(handlers: RemoteCommandHandlers)
    func teardown()
}

@MainActor
final class PlaybackViewModel: ObservableObject {
    private let nowPlayingInfoCenter: NowPlayingInfoCenterUpdating
    private let remoteCommands: RemoteCommandCenterHandling
    private var remoteCommandsConfigured = false

    private func handleStateChange(_ state: NowPlayingState?) {
        nowPlaying = state

        guard let state else {
            nowPlayingInfoCenter.clear()
            return
        }

        if remoteCommandsConfigured == false {
            remoteCommands.configure(
                handlers: RemoteCommandHandlers(
                    onPlay: { [weak self] in self?.playIfPaused() },
                    onPause: { [weak self] in self?.pauseIfPlaying() },
                    onNext: { [weak self] in self?.skipToNext() },
                    onPrevious: { [weak self] in self?.skipToPrevious() }
                )
            )
            remoteCommandsConfigured = true
        }

        let metadata = LockScreenNowPlayingMetadata(
            title: state.trackTitle,
            artist: state.artistName,
            albumTitle: nowPlayingContext?.album.title,
            elapsedTime: state.elapsedTime,
            duration: state.duration,
            isPlaying: state.isPlaying,
            artworkImage: currentArtworkImage
        )
        nowPlayingInfoCenter.update(with: metadata)
    }

    func stop() {
        engine?.stop()
        nowPlayingInfoCenter.clear()
        if remoteCommandsConfigured {
            remoteCommands.teardown()
            remoteCommandsConfigured = false
        }
    }
}
```

## Test Strategy
- Unit tests (`PlaybackViewModelTests`):
  - On state update, metadata updater receives expected fields (title/artist/album/elapsed/duration/isPlaying).
  - Metadata updater includes artwork image when resolver returns an image.
  - Metadata updater omits artwork when resolver returns nil.
  - On elapsed-time updates, metadata updater is called with new elapsed value.
  - `stop()` clears now-playing metadata.
  - Remote command registration occurs once when playback becomes active.
  - Remote command callbacks invoke:
    - play/pause pathway correctly
    - next
    - previous
  - Sign-out path still clears playback and lock-screen metadata via existing `stop()` call.

- Adapter tests:
  - `MPNowPlayingInfoCenter` mapping contains expected keys:
    - `MPMediaItemPropertyTitle`
    - `MPMediaItemPropertyArtist`
    - `MPMediaItemPropertyAlbumTitle`
    - `MPNowPlayingInfoPropertyElapsedPlaybackTime`
    - `MPMediaItemPropertyPlaybackDuration` (when duration present)
    - `MPNowPlayingInfoPropertyPlaybackRate`
    - `MPMediaItemPropertyArtwork` (when artwork is available)
  - Remote command center handlers return `.success` and correctly detach on teardown.

## Risks / Tradeoffs
- Remote command handler duplication can occur if registration/teardown is not idempotent.
- Play/Pause command semantics vary by source; guard conditions should avoid toggling into wrong state.
- Lock-screen updates on every second-level tick may be chatty; acceptable for v1, but can be throttled later if needed.
- Artwork decoding/resizing can add overhead; cache and downsample before creating `MPMediaItemArtwork`.

## Implementation Handoff (For `feature-implementation`)
1. Tests first (required)
- Add `PlaybackViewModel` unit tests for metadata updates, remote command wiring, and artwork present/absent behavior.
- Add adapter unit tests for `MPNowPlayingInfoCenter` mapping (including artwork) and command handler configure/teardown idempotency.

2. Implementation order
- Add files:
  - `Lunara/Playback/NowPlayingInfoCenterUpdater.swift`
  - `Lunara/Playback/RemoteCommandCenterHandler.swift`
  - `Lunara/Playback/LockScreenArtworkProvider.swift`
- Inject adapters into `PlaybackViewModel` with production defaults.
- Extend metadata model with optional artwork image.
- Resolve artwork on context changes and republish now-playing info.

3. Definition of done for this slice
- All `1.13` acceptance criteria in this doc pass, including artwork.
- Unit tests fully cover new lock-screen metadata/remote-command/artwork behavior.
- `docs/project-plan.md` remains aligned with scope and progress.
