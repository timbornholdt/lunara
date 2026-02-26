import Foundation
import UIKit
import SwiftUI

enum LunaraColorPreset: String, CaseIterable, Sendable {
    case oliveGrove

    var displayName: String {
        switch self {
        case .oliveGrove: return "Olive Grove"
        }
    }

    var description: String {
        switch self {
        case .oliveGrove: return "Sage and cream. Sunlit field notes."
        }
    }
}

@Observable
@MainActor
final class ColorSchemeManager {
    var preset: LunaraColorPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: ColorSchemeManager.presetKey)
            refreshToken = UUID()
        }
    }

    var refreshToken = UUID()

    private static let presetKey = "lunara_color_preset"

    init() {
        let raw = UserDefaults.standard.string(forKey: ColorSchemeManager.presetKey) ?? ""
        self.preset = LunaraColorPreset(rawValue: raw) ?? .oliveGrove
    }
}

struct ColorSchemeSettings: Equatable, Sendable {
    var preset: LunaraColorPreset

    static let `default` = ColorSchemeSettings(preset: .oliveGrove)

    private static let presetKey = "lunara_color_preset"

    static func load() -> ColorSchemeSettings {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: presetKey) ?? ""
        let preset = LunaraColorPreset(rawValue: raw) ?? ColorSchemeSettings.default.preset
        return ColorSchemeSettings(preset: preset)
    }

    func save() {
        UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
    }
}
