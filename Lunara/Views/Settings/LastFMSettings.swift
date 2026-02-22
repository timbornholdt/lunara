import Foundation

struct LastFMSettings: Equatable, Sendable {
    var isEnabled: Bool

    static let `default` = LastFMSettings(isEnabled: true)

    private static let isEnabledKey = "lastfm_scrobbling_enabled"

    static func load() -> LastFMSettings {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: isEnabledKey) as? Bool ?? LastFMSettings.default.isEnabled
        return LastFMSettings(isEnabled: enabled)
    }

    func save() {
        UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
    }
}
