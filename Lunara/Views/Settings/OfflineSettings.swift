import Foundation

struct OfflineSettings: Equatable, Sendable {
    var storageLimitGB: Double
    var wifiOnly: Bool

    var storageLimitBytes: Int64 {
        Int64(storageLimitGB * 1024 * 1024 * 1024)
    }

    static let `default` = OfflineSettings(storageLimitGB: 128, wifiOnly: true)

    private static let storageLimitKey = "offline_storage_limit_gb"
    private static let wifiOnlyKey = "offline_wifi_only"

    static func load() -> OfflineSettings {
        let defaults = UserDefaults.standard
        let limit = defaults.object(forKey: storageLimitKey) as? Double ?? OfflineSettings.default.storageLimitGB
        let wifi = defaults.object(forKey: wifiOnlyKey) as? Bool ?? OfflineSettings.default.wifiOnly
        return OfflineSettings(storageLimitGB: limit, wifiOnly: wifi)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(storageLimitGB, forKey: Self.storageLimitKey)
        defaults.set(wifiOnly, forKey: Self.wifiOnlyKey)
    }
}
