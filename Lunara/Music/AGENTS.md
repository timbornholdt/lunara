# AGENTS.md — Music Domain

You are working inside the Music Domain. Read the root `AGENTS.md` and `README.md` if you haven't already.

## Boundary Rules
- This domain owns: PlaybackEngine, QueueManager, NowPlayingBridge, AudioSession.
- This domain **never imports anything from the Library domain** (`Library/` directory). It does not know about Plex, albums, collections, or artwork. It plays URLs and manages a queue of tracks.
- Shared types from `Shared/` are fine to import and use.

## PlaybackEngine
- Uses `AVQueuePlayer` under the hood.
- Must support `prepareNext(url:trackID:)` for preloading the next track. QueueManager calls this proactively.
- Must publish `PlaybackState` including `.buffering`. The UI depends on all five states being accurate.
- On stream error or network loss: transition to `.error(message)`. Never play silence. Never hang in `.buffering` indefinitely — use a timeout.
- Does not know about the queue. It plays what it's told and reports what happened.

## QueueManager
- Observes PlaybackEngine for "track ended" events and advances automatically.
- Calls `prepareNext()` on PlaybackEngine whenever the queue changes or a new track starts.
- Persists its own state (queue contents, current index, elapsed position) separately from LibraryStore. Use its own file or lightweight database.
- On app relaunch: restore state but do NOT auto-play. Wait for explicit user action.

## AudioSession
- Category: `.playback`. This is a music player — audio must continue in background and with the screen locked.
- Handle interruptions (phone calls, Siri): pause on interruption begin, optionally resume on interruption end.
- Must be configured before the first `play()` call.

## NowPlayingBridge
- This is iOS system integration glue. Keep it small (~100 lines).
- Observes PlaybackEngine and QueueManager. Updates MPNowPlayingInfoCenter and MPRemoteCommandCenter.
- Does not contain business logic.
