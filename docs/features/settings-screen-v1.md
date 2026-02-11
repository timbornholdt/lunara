# Settings Screen v1 (Sign Out + De-dup Debug Toggle)

## Goal
Add a dedicated, extensible settings screen that centralizes account/session actions, exposes a runtime toggle for album de-dup debug logging, and supports future A/B experiment toggles with minimal code churn.

## Requirements
- Replace the current top-right "Sign Out" action with a gear icon entry point to Settings.
- Gear entry point is present in all three main browse tabs (Collections, Albums, Artists).
- Settings screen includes a Sign Out action.
- Settings screen includes a toggle to enable/disable album de-dup debug logging.
- De-dup debug logging preference persists across app launches.
- Settings architecture is extensible so new toggle-based feature flags/experiments can be added without modifying screen structure.
- Existing browse/navigation behavior remains unchanged.

## Acceptance Criteria
- Collections, Albums, and Artists tabs use a gear icon instead of a direct "Sign Out" button.
- Tapping the gear icon opens Settings.
- Settings includes:
  - A "Enable album de-dup debug logging" toggle.
  - A "Sign Out" action.
- Adding a new toggle setting requires only:
  - a new settings key/descriptor,
  - optional behavior wiring,
  - no structural rewrite of `SettingsView`.
- Sign Out clears auth state and returns user to sign-in flow.
- When debug logging is off, duplicate-album debug logs are not emitted.
- When debug logging is on, duplicate-album debug logs are emitted during dedupe passes.

## Constraints
- No third-party dependencies.
- Keep implementation SwiftUI-first and aligned with existing MVVM/store patterns.
- Maintain polished, technical error messaging style already used in app.

## Repository Context
- Relevant files:
  - `/Users/timbornholdt/Repos/Lunara/Lunara/ContentView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/LibraryBrowseView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/CollectionsBrowseView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/Views/ArtistsBrowseView.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/UI/LibraryViewModel.swift`
  - `/Users/timbornholdt/Repos/Lunara/Lunara/Plex/PlexUserDefaultsStores.swift`
- Existing patterns:
  - Shared root container (`MainTabView`) owns global sheet presentation and passes closures into tab views.
  - Persistent lightweight prefs currently use UserDefaults-backed store structs with protocol-style abstraction.
  - Session/logout is coordinated through `AuthViewModel.signOut()` and injected callbacks.

## Options Considered
### Option A: Root-presented settings sheet + dedicated UserDefaults settings store (Recommended)
- Add `AppSettingsStoring` + `UserDefaultsAppSettingsStore` for `isAlbumDedupDebugEnabled`.
- Define settings rows from typed descriptors (label, key path, group) to keep the view extensible for future A/B toggles.
- Present `SettingsView` as a root-level sheet from `MainTabView`.
- Replace toolbar sign-out actions with gear buttons that trigger the sheet.
- `LibraryViewModel` consults settings store at dedupe logging call site.
- Pros:
  - Clean separation of concerns; easy to unit test.
  - Single presentation path across tabs, consistent with Now Playing architecture.
  - Minimal risk to existing auth/navigation flows.
- Cons:
  - Small plumbing changes across multiple view initializers.

### Option B: AppStorage-backed toggle directly in `LibraryViewModel` and per-tab inline settings navigation
- Use `@AppStorage` in UI/view model and push settings screen per tab.
- Pros:
  - Faster to wire initially.
- Cons:
  - Tighter framework coupling in view model layer.
  - Duplicated presentation logic and higher regression risk.

### Option C: Keep direct sign-out and add only a debug toggle somewhere in library UI
- Pros:
  - Lowest code delta.
- Cons:
  - Fails explicit acceptance criteria for dedicated settings flow.

## Decision
Adopt Option A.

Rationale:
- Best alignment with established root-level presentation pattern.
- Preserves clean test seams (store protocol injection into `LibraryViewModel`).
- Supports future settings growth without repeated toolbar action churn.

## Proposed Approach
1. Introduce settings persistence
- Add protocol:
  - `AppSettingsStoring` with `var isAlbumDedupDebugEnabled: Bool { get set }`
- Add optional experiment toggles container (initially empty or seeded with one debug flag) to avoid one-off hardcoding for each future toggle.
- Add concrete store:
  - `UserDefaultsAppSettingsStore` key: `app.settings.albumDedupDebugEnabled`
  - Default `false`.
  - Reserve namespace for experiment keys: `app.settings.experiment.<flagName>`.

2. Add settings UI surface
- Create `SettingsView` (single screen) with:
  - Toggle rows rendered from a descriptor list (starting with de-dup debug logging).
  - Optional "Experiments" section populated from descriptor group in future.
  - Distinct destructive Sign Out button.
- Optional small `SettingsViewModel` to bridge store + actions.

3. Centralize settings presentation
- In `MainTabView`, add `@State private var showSettings = false`.
- Present `SettingsView` in `.sheet(isPresented:)`.
- Pass an `openSettings` closure into `LibraryBrowseView`, `CollectionsBrowseView`, and `ArtistsBrowseView`.
- Replace each trailing toolbar "Sign Out" button with gear icon button (`Image(systemName: "gearshape")`) calling `openSettings`.

4. Wire debug toggle into dedupe logging
- Remove compile-time constant `enableAlbumDedupDebug` from `LibraryViewModel`.
- Inject `settingsStore: AppSettingsStoring` into `LibraryViewModel`.
- Gate `logAlbumDedupDebug` by `settingsStore.isAlbumDedupDebugEnabled`.

5. Sign-out behavior in Settings
- Reuse existing sign-out closure passed from `ContentView` (`playbackViewModel.stop()` + `authViewModel.signOut()`).
- On sign-out tap:
  - dismiss settings sheet.
  - execute sign-out closure.

## Pseudocode
```swift
protocol AppSettingsStoring {
    var isAlbumDedupDebugEnabled: Bool { get set }
    func bool(for key: AppSettingBoolKey) -> Bool
    func set(_ value: Bool, for key: AppSettingBoolKey)
}

enum AppSettingBoolKey: String, CaseIterable {
    case albumDedupDebugLogging = "app.settings.albumDedupDebugEnabled"
    // Future: case newQueueAlgorithm = "app.settings.experiment.newQueueAlgorithm"
}

struct AppSettingToggleDescriptor: Identifiable {
    let id: AppSettingBoolKey
    let title: String
    let section: SectionKind
    enum SectionKind { case diagnostics, experiments }
}

struct UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults

    var isAlbumDedupDebugEnabled: Bool {
        get { bool(for: .albumDedupDebugLogging) }
        set { set(newValue, for: .albumDedupDebugLogging) }
    }

    func bool(for key: AppSettingBoolKey) -> Bool {
        defaults.object(forKey: key.rawValue) as? Bool ?? false
    }

    func set(_ value: Bool, for key: AppSettingBoolKey) {
        defaults.set(value, forKey: key.rawValue)
    }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    private var settingsStore: AppSettingsStoring

    init(..., settingsStore: AppSettingsStoring = UserDefaultsAppSettingsStore(), ...) {
        self.settingsStore = settingsStore
    }

    private func loadAlbums(section: PlexLibrarySection) async throws {
        let fetchedAlbums = try await service.fetchAlbums(sectionId: section.key)
        if settingsStore.isAlbumDedupDebugEnabled {
            logAlbumDedupDebug(albums: fetchedAlbums)
        }
        albums = dedupeAlbums(fetchedAlbums)
    }
}

struct SettingsView: View {
    let toggleDescriptors: [AppSettingToggleDescriptor]
    @State var toggleValues: [AppSettingBoolKey: Bool]
    let onToggle: (AppSettingBoolKey, Bool) -> Void
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Diagnostics") {
                    ForEach(toggleDescriptors.filter { $0.section == .diagnostics }) { item in
                        Toggle(item.title, isOn: binding(for: item.id))
                    }
                }

                Section("Experiments") {
                    ForEach(toggleDescriptors.filter { $0.section == .experiments }) { item in
                        Toggle(item.title, isOn: binding(for: item.id))
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) { onSignOut() }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func binding(for key: AppSettingBoolKey) -> Binding<Bool> {
        Binding(
            get: { toggleValues[key] ?? false },
            set: { newValue in
                toggleValues[key] = newValue
                onToggle(key, newValue)
            }
        )
    }
}

struct MainTabView: View {
    @State private var showSettings = false

    var body: some View {
        TabView {
            LibraryBrowseView(openSettings: { showSettings = true }, ...)
            CollectionsBrowseView(openSettings: { showSettings = true }, ...)
            ArtistsBrowseView(openSettings: { showSettings = true }, ...)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(...)
        }
    }
}
```

## Test Strategy
- Unit tests:
  - `UserDefaultsAppSettingsStore` defaults to `false` and persists `true/false`.
  - `LibraryViewModel` emits de-dup logs only when setting is enabled (inject test store + assert print/log sink behavior).
  - Settings sign-out action calls provided closure.
- View-model/UI behavior tests:
  - Gear action toggles settings presentation state in root container.
  - Toggle mutation updates persistent store immediately.
- Regression tests:
  - Existing library load + dedupe tests still pass with new injected settings store.

## Risks / Tradeoffs
- `print`-based logging is hard to assert directly; introduce a lightweight logger sink if unit assertions on logging output are required.
- A generic descriptor-driven settings UI adds a small upfront abstraction, but it reduces future effort and risk when adding experiment toggles.

## Open Questions
- None.
