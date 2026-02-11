import Foundation

final class UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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
