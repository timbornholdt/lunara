import Foundation
import Combine

struct AppSettingToggleDescriptor: Identifiable, Sendable {
    enum Section: String, Sendable {
        case diagnostics
        case experiments
    }

    let id: AppSettingBoolKey
    let title: String
    let section: Section
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var isSignOutConfirmationPresented = false

    let signOutConfirmationTitle = "Bail on your hi-fi hideout?"
    let signOutConfirmationMessage = "You can leave, but the records will judge you. Sign out anyway?"
    let signOutConfirmationButtonTitle = "Yep, sign me out"

    var diagnosticToggles: [AppSettingToggleDescriptor] {
        toggleDescriptors.filter { $0.section == .diagnostics }
    }

    var experimentToggles: [AppSettingToggleDescriptor] {
        toggleDescriptors.filter { $0.section == .experiments }
    }

    var showsEmptyExperimentsState: Bool {
        experimentToggles.isEmpty
    }

    private let settingsStore: AppSettingsStoring
    private let toggleDescriptors: [AppSettingToggleDescriptor]
    private let offlineLifecycleManager: OfflineDownloadsLifecycleManaging?
    private let onSignOut: () -> Void

    init(
        settingsStore: AppSettingsStoring,
        toggleDescriptors: [AppSettingToggleDescriptor]? = nil,
        offlineLifecycleManager: OfflineDownloadsLifecycleManaging? = OfflineServices.shared.coordinator,
        onSignOut: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.toggleDescriptors = toggleDescriptors ?? Self.defaultToggleDescriptors
        self.offlineLifecycleManager = offlineLifecycleManager
        self.onSignOut = onSignOut
    }

    func isEnabled(_ key: AppSettingBoolKey) -> Bool {
        settingsStore.bool(for: key)
    }

    func setToggle(_ key: AppSettingBoolKey, enabled: Bool) {
        settingsStore.set(enabled, for: key)
    }

    func requestSignOut() {
        isSignOutConfirmationPresented = true
    }

    func cancelSignOut() {
        isSignOutConfirmationPresented = false
    }

    func confirmSignOut() {
        isSignOutConfirmationPresented = false
        Task {
            try? await offlineLifecycleManager?.purgeAll()
            await MainActor.run {
                onSignOut()
            }
        }
    }

    private static let defaultToggleDescriptors: [AppSettingToggleDescriptor] = [
        AppSettingToggleDescriptor(
            id: .albumDedupDebugLogging,
            title: "Enable album de-dup debug logging",
            section: .diagnostics
        )
    ]
}
