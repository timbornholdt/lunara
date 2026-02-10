# AVPlayer Album Playback (Phase 1.3)

## Goal
Enable reliable album playback with AVPlayer, supporting:
- Tap-to-play from any track with sequential continuation.
- A dedicated play button on the album detail screen.
- Background audio playback.
- A future-proof playback source model that can switch between remote and local cached files.

## Requirements
- Playback starts from a tapped track and continues sequentially through the album.
- A Play button (with `|>` icon) appears under the star rating on the album detail screen.
- Album playback uses AVPlayer (queue-based).
- Background audio is supported via AVAudioSession configured for playback.
- Playback prefers direct-play URLs built from Plex `Media.Part.key`.
- If direct play fails, fallback to a Plex transcode URL for that track (MP3, 128kbps).
- Playback architecture must allow local cached file playback in a future phase without changing the player.

## Acceptance Criteria
- User can tap any track row and playback begins at that track, then proceeds in order to the end.
- User can tap the Play button to start from the first track.
- Playback continues when the app is backgrounded or the screen locks.
- Playback does not truncate on network changes (AVQueuePlayer remains active and continues to load).
- If a direct-play URL fails, playback retries with a transcode URL (MP3, 128kbps) and continues.
- Playback source selection is abstracted so local cached files can be used later without refactoring the player.

## Constraints
- No third-party dependencies.
- Preserve existing SwiftUI + MVVM patterns.
- Avoid introducing Plex play-queue endpoints unless required.

## Repository Context
- Relevant files:
  - `Lunara/UI/Views/AlbumDetailView.swift`
  - `Lunara/UI/AlbumDetailViewModel.swift`
  - `Lunara/Plex/Library/PlexModels.swift`
  - `Lunara/Plex/Library/PlexLibraryService.swift`
  - `Lunara/Plex/Library/PlexLibraryRequestBuilder.swift`
  - `Lunara/Plex/PlexProtocols.swift`
- Existing patterns:
  - View models own async loading and error states.
  - Plex request builders are small, testable structs.
  - Services are protocol-first and injected via factories.

## Proposed Approach
1. **Extend track decoding** to include `Media` and `Part` so we can access a direct-play `key` for each track.
2. **Introduce playback source resolution**:
   - `PlaybackSourceResolver` returns a `PlaybackSource` for a track.
   - For now, it will return `.remote(directPlayURL)` if a part key exists.
   - Later, it can return `.local(fileURL)` if cached.
3. **Playback URL builder**:
   - `PlexPlaybackURLBuilder` builds:
     - Direct-play URLs from `Part.key` plus `X-Plex-Token`.
     - Transcode URLs for fallback (exact params TBD, but enough to stream if direct fails).
4. **Playback engine**:
   - `PlaybackEngine` uses `AVQueuePlayer`.
   - Given a list of tracks and a start index, it creates an ordered queue of items.
   - The engine provides state updates: current track, isPlaying, and failure reasons.
5. **View model coordination**:
   - `AlbumDetailViewModel` owns a `PlaybackEngine` (or a `PlaybackControlling` protocol).
   - Track tap or Play button triggers `play(tracks:startIndex:)`.
   - View model exposes a `NowPlayingState` for UI display.
6. **Background audio**:
   - Configure `AVAudioSession` with `.playback`, `.default`, and activate on play.
7. **Now playing state**:
   - Track title, isPlaying, elapsed time, and duration are exposed for UI.

## Alternatives Considered
1. **Plex Play Queue endpoints**
   - Pros: Plex-managed playback session.
   - Cons: More endpoints, not required for offline parity.
2. **Transcode-only playback**
   - Pros: consistent audio format.
   - Cons: more server load, less aligned with offline file playback.

## Pseudocode
```swift
enum PlaybackSource {
    case remote(url: URL)
    case local(fileURL: URL)
}

protocol PlaybackSourceResolving {
    func resolveSource(for track: PlexTrack) -> PlaybackSource?
}

final class PlaybackSourceResolver: PlaybackSourceResolving {
    let localIndex: LocalPlaybackIndex?
    let urlBuilder: PlexPlaybackURLBuilder

    func resolveSource(for track: PlexTrack) -> PlaybackSource? {
        if let fileURL = localIndex?.fileURL(for: track.ratingKey) {
            return .local(fileURL: fileURL)
        }
        guard let partKey = track.media?.first?.parts?.first?.key else { return nil }
        return .remote(url: urlBuilder.makeDirectPlayURL(partKey: partKey))
    }
}

protocol PlaybackControlling {
    func play(tracks: [PlexTrack], startIndex: Int)
    func stop()
    var state: PlaybackState { get }
}

final class PlaybackEngine: PlaybackControlling {
    let player = AVQueuePlayer()
    let resolver: PlaybackSourceResolving
    let urlBuilder: PlexPlaybackURLBuilder

    func play(tracks: [PlexTrack], startIndex: Int) {
        configureAudioSession()
        let queue = tracks.compactMap { track in
            resolver.resolveSource(for: track).map { source in
                AVPlayerItem(url: source.url)
            }
        }
        player.removeAllItems()
        queue.forEach { player.insert($0, after: nil) }
        skipToIndex(startIndex)
        player.play()
    }

    private func handleItemFailure(track: PlexTrack) {
        guard let fallback = urlBuilder.makeTranscodeURL(trackRatingKey: track.ratingKey) else { return }
        replaceCurrentItem(with: AVPlayerItem(url: fallback))
        player.play()
    }
}

struct NowPlayingState {
    let trackTitle: String
    let artistName: String?
    let isPlaying: Bool
    let trackIndex: Int
    let elapsedTime: TimeInterval
    let duration: TimeInterval?
}
```

## Test Strategy
- Unit tests:
  - Track decoding includes `Media.Part.key`.
  - `PlexPlaybackURLBuilder` builds correct URLs for direct play and transcode.
  - `PlaybackSourceResolver` prefers local files, otherwise remote.
  - `PlaybackEngine` builds queue in track order and starts at correct index.
  - Fallback logic triggers transcode URL on direct-play failure.
  - `AlbumDetailViewModel` updates now-playing state and handles play actions.
- Edge cases:
  - Missing part key (no direct-play URL).
  - Track list empty.
  - Start index out of range (clamps to 0).
  - Direct-play fails mid-track and fallback succeeds.

## Risks / Tradeoffs
- Plex direct-play can fail for unsupported codecs; fallback mitigates but needs correct transcode params.
- AVQueuePlayer does not support custom headers; URLs must embed tokens.
- Background playback requires Info.plist audio capability if needed; verify existing project settings.

## Open Questions
- None.
