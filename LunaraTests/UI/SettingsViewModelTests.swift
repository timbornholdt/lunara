import Foundation
import Testing
@testable import Lunara

@MainActor
struct SettingsViewModelTests {
    @Test func diagnosticsSectionContainsDedupToggle() {
        let store = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(settingsStore: store, onSignOut: {})

        let diagnosticsKeys = viewModel.diagnosticToggles.map(\.id)
        #expect(diagnosticsKeys.contains(.albumDedupDebugLogging))
    }

    @Test func experimentsSectionIsVisibleWithEmptyStateWhenNoExperimentToggles() {
        let store = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            toggleDescriptors: [
                .init(id: .albumDedupDebugLogging, title: "Enable album de-dup debug logging", section: .diagnostics)
            ],
            onSignOut: {}
        )

        #expect(viewModel.experimentToggles.isEmpty)
        #expect(viewModel.showsEmptyExperimentsState == true)
    }

    @Test func settingToggleWritesThroughToStore() {
        let store = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(settingsStore: store, onSignOut: {})

        viewModel.setToggle(.albumDedupDebugLogging, enabled: true)

        #expect(store.bool(for: .albumDedupDebugLogging) == true)
        #expect(viewModel.isEnabled(.albumDedupDebugLogging) == true)
    }

    @Test func experimentsSectionHidesEmptyStateWhenTogglesExist() {
        let store = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            toggleDescriptors: [
                .init(id: .newQueueAlgorithm, title: "Use new queue algorithm", section: .experiments)
            ],
            onSignOut: {}
        )

        #expect(viewModel.showsEmptyExperimentsState == false)
        #expect(viewModel.experimentToggles.map(\.id) == [.newQueueAlgorithm])
    }

    @Test func signOutUsesConfirmationAndCallsCallbackOnlyAfterConfirm() async {
        let store = InMemoryAppSettingsStore()
        var signOutCount = 0
        let lifecycle = RecordingOfflineLifecycleManager()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            offlineLifecycleManager: lifecycle,
            cacheStore: InMemoryLibraryCacheStore(),
            onSignOut: { signOutCount += 1 }
        )

        viewModel.requestSignOut()
        #expect(viewModel.isSignOutConfirmationPresented == true)
        #expect(signOutCount == 0)

        viewModel.confirmSignOut()
        while signOutCount == 0 {
            await Task.yield()
        }
        #expect(signOutCount == 1)
        #expect(lifecycle.purgeCallCount == 1)
        #expect(viewModel.isSignOutConfirmationPresented == false)
    }

    @Test func canCancelSignOutConfirmation() {
        let store = InMemoryAppSettingsStore()
        let viewModel = SettingsViewModel(settingsStore: store, onSignOut: {})

        viewModel.requestSignOut()
        #expect(viewModel.isSignOutConfirmationPresented == true)

        viewModel.cancelSignOut()
        #expect(viewModel.isSignOutConfirmationPresented == false)
    }
}

private final class RecordingOfflineLifecycleManager: OfflineDownloadsLifecycleManaging {
    private(set) var purgeCallCount = 0

    func purgeAll() async throws {
        purgeCallCount += 1
    }
}
