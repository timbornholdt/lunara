import Foundation
import Testing
@testable import Lunara

struct AppSettingsStoreTests {
    @Test func defaultsDedupDebugLoggingToFalse() {
        let defaults = makeDefaults()
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        #expect(store.isAlbumDedupDebugEnabled == false)
    }

    @Test func persistsDedupDebugLoggingToggle() {
        let defaults = makeDefaults()
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        store.isAlbumDedupDebugEnabled = true
        let reloaded = UserDefaultsAppSettingsStore(defaults: defaults)

        #expect(reloaded.isAlbumDedupDebugEnabled == true)
    }

    @Test func defaultsUnknownExperimentToggleToFalse() {
        let defaults = makeDefaults()
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        #expect(store.bool(for: .newQueueAlgorithm) == false)
    }

    @Test func persistsExperimentToggleValue() {
        let defaults = makeDefaults()
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        store.set(true, for: .newQueueAlgorithm)
        let reloaded = UserDefaultsAppSettingsStore(defaults: defaults)

        #expect(reloaded.bool(for: .newQueueAlgorithm) == true)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
