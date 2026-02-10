# Initial Screen

## Goal
Provide a branded initial screen that appears on app launch while the saved session is validated, then routes to the library or sign-in screen.

## Requirements
- Show a linen background with a simple geometric emblem, the text "Lunara", and a loading indicator when the app loads.
- Validate any stored token/session on launch.
- If the session is valid, transition directly into the library view.
- If the user is not signed in or the session is invalid, show the login screen.
 - When validation completes, the initial screen should fade out.

## Acceptance Criteria
- On app launch, a branded initial screen is visible until the initial token check finishes.
- When the token is valid, the app routes to the main library tab view without showing the sign-in view.
- When the token is missing or invalid, the app routes to the sign-in view.
- The initial screen includes:
  - A linen background
  - A simple geometric emblem (non-asset is OK)
  - The "Lunara" wordmark text
  - A loading indicator
 - The initial screen fades out when validation completes.

## Constraints
- Follow `docs/ui-brand-guide.md` typography and palette.
- No third-party dependencies.
- Reuse existing theme assets (linen background, palette) when possible.

## Repository Context
- Entry routing: `/Users/timbornholdt/Repos/Lunara/Lunara/ContentView.swift`
- Auth session check: `/Users/timbornholdt/Repos/Lunara/Lunara/UI/AuthViewModel.swift`
  - `loadToken()` runs on init and sets `didFinishInitialTokenCheck`.
- Sign-in UI: `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/SignInView.swift`
- Theme + background: `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Styles/LunaraTheme.swift`, `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Styles/LinenBackgroundView.swift`

## Proposed Approach
- Add a lightweight `InitialScreenView` that uses the linen background, a simple geometric emblem (e.g., circular "record" + inset ring or a rounded square "album" tile), the "Lunara" title, and a `ProgressView` tinted with the accent color.
- Update `ContentView` routing to show the initial screen while `authViewModel.didFinishInitialTokenCheck == false`. After the check completes, fade out the initial screen and route to `MainTabView` or `SignInView` based on `isAuthenticated`.
- Keep the initial screen purely presentational; it reflects the `AuthViewModel` lifecycle without adding new network behavior.

## Alternatives Considered
1. **Show sign-in immediately and overlay a loading indicator**
   - Pros: Fewer views.
   - Cons: Sign-in flashes before validation; does not meet "initial screen" requirement.
2. **Use app icon image asset**
   - Pros: Strong brand tie-in.
   - Cons: Requires asset management and design approval; less flexible for theming.

## Pseudocode
```
ContentView.body:
  if !authViewModel.didFinishInitialTokenCheck:
      InitialScreenView()
  else if authViewModel.isAuthenticated:
      MainTabView(...)
  else:
      SignInView(viewModel: authViewModel)

InitialScreenView:
  ZStack:
    LinenBackgroundView(palette)
    VStack:
      EmblemGraphicView() // simple shapes using accent/border colors
      Text("Lunara") with display font
      ProgressView() tinted accent
```

## Test Strategy
- Unit tests (Swift Testing):
  - Add an `AuthViewModel.launchState` or `isCheckingSession` computed property to make routing testable.
  - Verify state transitions for:
    - valid stored token -> `authenticated`
    - missing token -> `unauthenticated`
    - invalid token -> `unauthenticated` + error set
    - validation failure non-401 -> `authenticated` with status message
- UI smoke test (manual):
  - Launch app with a valid token in Keychain -> initial screen briefly, then library.
  - Launch with no token -> initial screen briefly, then sign-in screen.

## Risks / Tradeoffs
- If routing remains purely in `ContentView` without a testable state enum, unit testing view logic is harder.
- If the initial screen uses an image asset, it will require additional asset management and likely design iteration.

## Open Questions
- None.
```
