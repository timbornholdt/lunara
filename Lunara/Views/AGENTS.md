# AGENTS.md — Views

You are working on SwiftUI views. Read the root `AGENTS.md` and `README.md` if you haven't already.

## Rules
- Views send **actions** through `AppRouter`. Views **observe** state directly from LibraryRepo (for data) and Music Domain (for playback state).
- Views never call PlexAPIClient, LibraryStore, or PlaybackEngine directly.
- Views never perform business logic. If a view is doing more than binding data and sending actions, logic needs to move to the router or a domain.

## PlaybackState Handling
- **Every view that displays playback state must handle all five cases:** `idle`, `buffering`, `playing`, `paused`, `error(String)`.
- The `buffering` state must show a visible loading indicator. It must never look identical to `paused` or `idle`.
- The `error` state must show the error banner component.

## Error Display
- Use the shared error banner component (non-blocking toast at top of screen).
- Don't use `alert()` dialogs for errors — they block interaction.

## Design Language
- Playfair Display for headings/display text. San Francisco (system) for body/controls.
- Linen background texture (programmatic, not static asset).
- Pill-shaped buttons. Card-style inputs.
- Transitions: slides, fades, springs. No jarring cuts. Minimal animation during active listening.
- Album artwork uses the Artwork Pipeline: show placeholder immediately, load from disk cache, fall back to async network fetch. Never block the UI waiting for artwork.

## File Size
- Keep view files under 300 lines. Extract subviews into their own files when a view grows.
- Put reusable components in `Views/Components/`.
