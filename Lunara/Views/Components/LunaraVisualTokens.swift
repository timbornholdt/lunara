import CoreGraphics
import SwiftUI

enum LunaraSemanticColorRole: CaseIterable {
    case backgroundBase
    case backgroundElevated
    case textPrimary
    case textSecondary
    case accentPrimary
    case accentOnAccent
    case borderSubtle
}

enum LunaraHeadingLevel: CaseIterable {
    case display
    case title
    case section
}

enum LunaraHeadingWeight: CaseIterable {
    case regular
    case semibold
}

enum LunaraPillButtonRole: CaseIterable {
    case primary
    case secondary
    case destructive
}

struct LunaraColorToken: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
}

struct LunaraHeadingToken: Equatable {
    let preferredFontName: String
    let fallbackWeight: Font.Weight
    let size: CGFloat
    let relativeTextStyle: Font.TextStyle
}

struct LunaraPillButtonToken: Equatable {
    let backgroundRole: LunaraSemanticColorRole
    let foregroundRole: LunaraSemanticColorRole
    let borderRole: LunaraSemanticColorRole?
}

struct LunaraLinenToken: Equatable {
    let horizontalOpacity: Double
    let verticalOpacity: Double
    let horizontalLineSpacing: CGFloat
    let verticalLineSpacing: CGFloat
}

enum LunaraVisualTokens {
    static func colorToken(for role: LunaraSemanticColorRole, in scheme: ColorScheme) -> LunaraColorToken {
        switch scheme {
        case .dark:
            return darkColorToken(for: role)
        case .light:
            let preset = ColorSchemeSettings.load().preset
            return lightColorToken(for: role, preset: preset)
        @unknown default:
            let preset = ColorSchemeSettings.load().preset
            return lightColorToken(for: role, preset: preset)
        }
    }

    // MARK: - Dark mode (unchanged)

    private static func darkColorToken(for role: LunaraSemanticColorRole) -> LunaraColorToken {
        // 90s Retro Pop: navy, hot pink, teal, golden yellow
        switch role {
        case .backgroundBase:
            return LunaraColorToken(red: 0.102, green: 0.102, blue: 0.243, opacity: 1.0)
        case .backgroundElevated:
            return LunaraColorToken(red: 0.165, green: 0.165, blue: 0.322, opacity: 1.0)
        case .textPrimary:
            return LunaraColorToken(red: 0.0, green: 0.788, blue: 0.690, opacity: 1.0)
        case .textSecondary:
            return LunaraColorToken(red: 0.973, green: 0.953, blue: 0.941, opacity: 0.7)
        case .accentPrimary:
            return LunaraColorToken(red: 0.910, green: 0.192, blue: 0.541, opacity: 1.0)
        case .accentOnAccent:
            return LunaraColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        case .borderSubtle:
            return LunaraColorToken(red: 0.941, green: 0.784, blue: 0.235, opacity: 0.50)
        }
    }

    // MARK: - Light mode presets

    // swiftlint:disable cyclomatic_complexity
    static func lightColorToken(for role: LunaraSemanticColorRole, preset: LunaraColorPreset) -> LunaraColorToken {
        switch preset {
        case .oliveGrove:
            // 90s Retro Pop: navy, hot pink, teal, golden yellow
            switch role {
            case .backgroundBase:
                return LunaraColorToken(red: 0.102, green: 0.102, blue: 0.243, opacity: 1.0)
            case .backgroundElevated:
                return LunaraColorToken(red: 0.165, green: 0.165, blue: 0.322, opacity: 1.0)
            case .textPrimary:
                return LunaraColorToken(red: 0.0, green: 0.788, blue: 0.690, opacity: 1.0)
            case .textSecondary:
                return LunaraColorToken(red: 0.973, green: 0.953, blue: 0.941, opacity: 0.7)
            case .accentPrimary:
                return LunaraColorToken(red: 0.910, green: 0.192, blue: 0.541, opacity: 1.0)
            case .accentOnAccent:
                return LunaraColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
            case .borderSubtle:
                return LunaraColorToken(red: 0.941, green: 0.784, blue: 0.235, opacity: 0.50)
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity

    static func colorToken(for role: LunaraSemanticColorRole) -> LunaraColorToken {
        colorToken(for: role, in: .light)
    }

    static func headingToken(for level: LunaraHeadingLevel, weight: LunaraHeadingWeight) -> LunaraHeadingToken {
        let preferredFontName: String
        let fallbackWeight: Font.Weight

        switch weight {
        case .regular:
            preferredFontName = "PlayfairDisplay-Regular"
            fallbackWeight = .regular
        case .semibold:
            preferredFontName = "PlayfairDisplay-SemiBold"
            fallbackWeight = .semibold
        }

        switch level {
        case .display:
            return LunaraHeadingToken(
                preferredFontName: preferredFontName,
                fallbackWeight: fallbackWeight,
                size: 40,
                relativeTextStyle: .largeTitle
            )
        case .title:
            return LunaraHeadingToken(
                preferredFontName: preferredFontName,
                fallbackWeight: fallbackWeight,
                size: 30,
                relativeTextStyle: .title
            )
        case .section:
            return LunaraHeadingToken(
                preferredFontName: preferredFontName,
                fallbackWeight: fallbackWeight,
                size: 22,
                relativeTextStyle: .title3
            )
        }
    }

    static func pillButtonToken(for role: LunaraPillButtonRole) -> LunaraPillButtonToken {
        switch role {
        case .primary:
            return LunaraPillButtonToken(
                backgroundRole: .accentPrimary,
                foregroundRole: .accentOnAccent,
                borderRole: nil
            )
        case .secondary:
            return LunaraPillButtonToken(
                backgroundRole: .backgroundElevated,
                foregroundRole: .textPrimary,
                borderRole: .borderSubtle
            )
        case .destructive:
            return LunaraPillButtonToken(
                backgroundRole: .textPrimary,
                foregroundRole: .accentOnAccent,
                borderRole: nil
            )
        }
    }

    static var linenToken: LunaraLinenToken {
        LunaraLinenToken(
            horizontalOpacity: 0.18,
            verticalOpacity: 0.12,
            horizontalLineSpacing: 3,
            verticalLineSpacing: 4
        )
    }
}
