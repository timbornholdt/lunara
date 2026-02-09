# Sign-In Brand Refresh (Phase 1.2)

## Goal
Bring the sign-in experience into compliance with `docs/ui-brand-guide.md`, including typography, color, layout, and a procedurally generated linen background that adapts to color scheme changes.

## Scope
- Sign-in screen only (`SignInView`).
- Shared UI utilities can be added (e.g., `LinenBackgroundView`, `LunaraButtonStyle`, `LunaraCardStyle`).

## Non-Goals
- No auth flow changes.
- No navigation changes outside the sign-in screen.
- No additional feature behavior beyond UI styling.

## Requirements
- Use Playfair Display for the "Lunara" title.
- Use Playfair Display Regular for body text.
- Apply the warm paper + moss palette from `docs/ui-brand-guide.md`.
- Primary CTA uses pill styling.
- Input field presented as a card (no default rounded border).
- Layout spacing matches the iPhone 15 Pro spec in `docs/ui-brand-guide.md`.
- Linen background is generated on the fly, not a static asset:
  - Must be subtle and professional (not noisy or gimmicky).
  - Should adapt to light/dark or theme changes by taking base colors as inputs.
  - Should be deterministic (no visible flicker between renders).

## Linen Background Approach
Generate a subtle linen texture procedurally in SwiftUI:
- Base: solid `bg/base` fill.
- Linen pattern: a faint crosshatch + noise layer using a seeded RNG to avoid flicker.
- Opacity: 3–6% for pattern overlays.
- Tile size: ~80–120pt, tiled across the screen.
- Should be cached (e.g., static `Image` per color scheme) to avoid redraw cost.

## Layout Spec (iPhone 15 Pro)
- Global padding: 20pt
- Spacing: 24pt between major blocks
- Title block:
  - "Lunara" in Playfair Display, 34pt, semibold
  - Subtitle in SF Pro, 17pt, secondary color
- Input card:
  - Height: 52pt
  - Corner radius: 12pt
  - Background: `bg/raised`
  - Border: `border/subtle`
- Primary CTA:
  - Height: 52pt
  - Pill radius
  - Fill: `accent/primary`

## Acceptance Criteria
- Sign-in screen matches the brand guide for typography, colors, and spacing.
- Linen background renders smoothly and adapts to color scheme changes.
- No functional regressions in the sign-in flow.

## Decisions Captured
- Playfair Display is used as the primary font for both display and body text.
- Linen background is generated procedurally and adapts to light/dark palettes.
