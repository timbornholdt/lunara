# UI + Brand Guide (Phase 0)

## Brand Direction
- Name usage: "Lunara" is the only product name shown in the UI. Avoid taglines in app chrome.
- Tone: Balanced and grounded. Short labels, low visual noise. Prefer verbs like "Play", "Save", "Download".
- Visual references: Hi‑fi hardware in a mid‑century modern cozy den (leather chair, impeccable gear), warm paper/linen textures, warm daylight + dusk contrast.
- Target device: iPhone 15 Pro (optimize for this size first).

## Typography System
- Display font: Playfair Display (serif, classic, editorial tone).
- Body font: Playfair Display Regular (custom).
- Hierarchy rules:
- Display: `LargeTitle` for album title on detail pages (Playfair Bold).
- Title: section headers and Now Playing title (Playfair Bold).
- Body: track rows, metadata, and long-form text (Playfair Regular).
- Caption: secondary metadata (Playfair Regular).
- Mono: `MonospacedDigit` for timecodes and progress.

Typography scale (iPhone 15 Pro, point sizes):
- Display (album title): 34pt, Playfair Display Bold, line height 1.15
- Section title: 22pt, Playfair Display Bold, line height 1.2
- Body: 17pt, Playfair Display Regular, line height 1.3
- Caption: 13pt, Playfair Display Regular, line height 1.2
- Timecode: 13pt, Playfair Display Regular + `MonospacedDigit`

## Color System
Base palette: warm neutral + muted green + deep dusk with gold highlight.
- `bg/base`: #F6F1EA (warm paper)
- `bg/raised`: #FFFCF7 (cards/sheets)
- `text/primary`: #1A1A18
- `text/secondary`: #5B5A55
- `accent/primary`: #3D5A4A (deep moss)
- `accent/secondary`: #C9A23A (gold highlight)
- `border/subtle`: #E4DED5
- `state/error`: #B33A3A
- `state/success`: #2E6B4E

Accessibility targets:
- Minimum 4.5:1 for body text against `bg/base`.
- Large titles can drop to 3:1 when used over solid `bg/raised`.

## Component Styling
- Buttons:
  - Primary: filled `accent/primary`, pill radius, white text.
  - Secondary: `bg/raised` with `border/subtle`, text in `accent/primary`.
  - Tertiary: text-only in `accent/primary`.
- Lists:
  - Album grids: 2-column on phone, 4 on iPad.
  - Rows: card-style containers with subtle separation (no zebra striping).
- Cards:
  - Very soft shadow (y=1, blur=8, ~8% opacity).
  - 12pt corner radius.
- Navigation:
  - Top nav with title only; avoid large toolbars.
- Now Playing:
  - Artwork is dominant; controls are clearly visible and centered.
- Icons:
  - Thin line style.
- Background:
  - Subtle linen texture on `bg/base` generated on the fly (no static asset).
  - Visual reference: https://www.toptal.com/designers/subtlepatterns/low-contrast-linen/
- Density:
  - Comfortable (airy), but keep album grids information-rich when scrolling.

Layout spec (iPhone 15 Pro):
- Global side padding: 20pt
- Section vertical spacing: 20pt
- Card corner radius: 12pt
- Card shadow: y=1, blur=8, opacity ~8%
- Album grid:
  - Columns: 2
  - Column spacing: 16pt
  - Row spacing: 18pt
  - Artwork card: square, 12pt radius
  - Title top padding: 10pt
  - Title: 15pt Playfair Display Bold, 2-line max, tail truncation
  - Subtitle (artist): 13pt Playfair Display Regular, 1-line max, tail truncation
- Album detail:
  - Artwork size: full width edge-to-edge (square)
  - Title block spacing: 10pt between title/artist, 6pt to metadata
  - User rating: stars aligned to title baseline, shown only if present
  - Action row spacing: 12pt top margin, 12pt horizontal gaps between buttons
  - Track row card: 12pt vertical padding, 14pt horizontal padding, 10pt gap between rows
  - Track row typography: title 17pt Playfair Display Regular, secondary 13pt Playfair Display Regular
  - Track number width: fixed 22pt, monospaced digit
  - Duration aligned trailing, monospaced digit

Now Playing layout spec (iPhone 15 Pro):
- Artwork:
  - Size: full width minus padding (square)
  - Top margin: 16pt
- Title block:
  - Title: 28pt Playfair Display Semibold, 2-line max, tail truncation
  - Artist: 17pt SF Pro Regular, 1-line max
  - Spacing: 10pt between title/artist, 8pt to controls
- Controls:
  - Primary row: Previous / Play-Pause / Next, centered
  - Button size: 44pt tap target, icons 22pt
  - Spacing: 26pt between buttons
- Scrubber:
  - Height: 4pt
  - Top margin: 18pt from controls
  - Timecodes: 13pt monospaced digit, 8pt below scrubber
- Secondary actions:
  - Row with `Play Next`, `Queue` (thin line icons + labels)
  - Top margin: 18pt from timecodes

Download placement:
- Downloads are initiated from Album Detail and Collection Detail screens.
- On All Albums grid, download is available via long-press context menu.

## Motion Rules
- Use smooth, present‑but‑restrained transitions:
  - Page push: 240ms ease‑out.
  - Modal/sheet: 280ms spring (low bounce).
  - Artwork fade-in: 200ms.
- Emphasis: progress bar uses subtle scale (1.0 -> 1.02) on interaction.
- Avoid continuous animations.

## Core Screen Mock (Album Detail)
Goal: confirm album-first, warm, tactile feel with hi‑fi den vibe.

Layout:
- Top: 1:1 album artwork card (rounded 12pt, shadow).
- Title block: album title (LargeTitle), artist (Title3), year/genre (Caption).
- Primary action row:
  - `Play Album` (primary button)
  - `Play Next` (secondary)
  - `Download` (tertiary icon + label)
- Track list:
  - Track number (Caption, monospaced digit)
  - Track title (Body)
  - Duration (Caption, monospaced digit)
- Footer: subtle metadata note (e.g., "24 tracks • 1h 42m").

ASCII mock:
```
╭──────────────────────────╮
│        ARTWORK           │
╰──────────────────────────╯
ALBUM TITLE
Artist Name
1999 • Ambient

[ Play Album ] [ Play Next ]   Download

01  Track Title One        3:54
02  Track Title Two        4:11
03  Track Title Three      5:02
...
24 tracks • 1h 42m
```
