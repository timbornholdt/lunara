# AGENTS.md — Music Domain

You are working inside the Music Domain. Read the root `AGENTS.md` and `README.md` if you haven't already.

## Boundary Rules
- This domain owns: PlaybackEngine, QueueManager, NowPlayingBridge, AudioSession, TrackCache.
- This domain **never imports anything from the Library domain** (`Library/` directory). It does not know about Plex, albums, collections, or artwork. It plays URLs and manages a queue of tracks.
- Shared types from `Shared/` are fine to import and use.

## PlaybackEngine
- Protocol-based (`PlaybackEngineProtocol`). Two implementations exist:
  - `AVQueuePlayerEngine`: original streaming engine (fallback).
  - `CrossfadeEngine` (active): dual-slot `AVAudioPlayer` engine with crossfade.
- Must publish `PlaybackState` including `.buffering`. The UI depends on all five states being accurate.
- On stream error or network loss: transition to `.error(message)`. Never play silence.
- Does not know about the queue. It plays what it's told and reports what happened.
- Crossfade-specific methods (`prepareNext`, `signalBuffering`, `skipWithFade`) have default no-op implementations so both engines compile.

## CrossfadeEngine
- Uses two `PlayerSlot` instances (A/B) that alternate as active/inactive.
- `PlayerSlot` wraps `AVAudioPlayer` — requires local file URLs (not streaming URLs).
- GCD `DispatchSourceTimer` for crossfade scheduling (background-safe). RunLoop `Timer` for UI elapsed updates only.
- Equal-power crossfade ramp (cos/sin). Skip uses a 500ms fade-out.
- `CrossfadePolicy` decides `TransitionStyle`: `.gapless` for consecutive same-album tracks, `.crossfade(startTime:duration:)` for cross-album. Duration (2–12s) derived from loudness analysis when available.

## TrackCache
- Actor-based, 5-file LRU cache. Downloads streaming URLs to temp local files for `AVAudioPlayer`.
- Skipped entirely for `file://` URLs (offline/downloaded tracks).
- Separate from the offline download store — this is a temporary playback cache.

## QueueManager
- Observes PlaybackEngine for "track ended" events and advances automatically.
- Computes `TransitionStyle` via `CrossfadePolicy` using `QueueItem.albumID` and `QueueItem.trackNumber`.
- Calls `prepareNext(url:trackID:transition:)` on PlaybackEngine with the computed transition.
- Syncs `currentIndex` when the engine completes a crossfade-driven track swap.
- Persists its own state (queue contents, current index, elapsed position) separately from LibraryStore.
- On app relaunch: restore state but do NOT auto-play. Wait for explicit user action.

## AudioSession
- Category: `.playback` with `.duckOthers`. This is a music player — audio must continue in background and with the screen locked.
- Handle interruptions (phone calls, Siri): pause on interruption begin, optionally resume on interruption end.
- Must be configured before the first `play()` call.

## NowPlayingBridge
- This is iOS system integration glue. Keep it small (~100 lines).
- Observes PlaybackEngine and QueueManager. Updates MPNowPlayingInfoCenter and MPRemoteCommandCenter.
- Does not contain business logic.
