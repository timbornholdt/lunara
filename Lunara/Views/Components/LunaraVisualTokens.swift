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
        switch role {
        case .backgroundBase:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.960, green: 0.949, blue: 0.863, opacity: 1.0)
            case .dark:
                return LunaraColorToken(red: 0.094, green: 0.114, blue: 0.086, opacity: 1.0)
            @unknown default:
                return LunaraColorToken(red: 0.960, green: 0.949, blue: 0.863, opacity: 1.0)
            }
        case .backgroundElevated:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.985, green: 0.968, blue: 0.807, opacity: 1.0)
            case .dark:
                return LunaraColorToken(red: 0.156, green: 0.196, blue: 0.122, opacity: 1.0)
            @unknown default:
                return LunaraColorToken(red: 0.985, green: 0.968, blue: 0.807, opacity: 1.0)
            }
        case .textPrimary:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.153, green: 0.204, blue: 0.133, opacity: 1.0)
            case .dark:
                return LunaraColorToken(red: 0.960, green: 0.951, blue: 0.834, opacity: 1.0)
            @unknown default:
                return LunaraColorToken(red: 0.153, green: 0.204, blue: 0.133, opacity: 1.0)
            }
        case .textSecondary:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.322, green: 0.384, blue: 0.251, opacity: 1.0)
            case .dark:
                return LunaraColorToken(red: 0.780, green: 0.773, blue: 0.639, opacity: 1.0)
            @unknown default:
                return LunaraColorToken(red: 0.322, green: 0.384, blue: 0.251, opacity: 1.0)
            }
        case .accentPrimary:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.412, green: 0.557, blue: 0.239, opacity: 1.0)
            case .dark:
                return LunaraColorToken(red: 0.807, green: 0.702, blue: 0.322, opacity: 1.0)
            @unknown default:
                return LunaraColorToken(red: 0.412, green: 0.557, blue: 0.239, opacity: 1.0)
            }
        case .accentOnAccent:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.989, green: 0.983, blue: 0.914, opacity: 1.0)
            case .dark:
                return LunaraColorToken(red: 0.129, green: 0.157, blue: 0.098, opacity: 1.0)
            @unknown default:
                return LunaraColorToken(red: 0.989, green: 0.983, blue: 0.914, opacity: 1.0)
            }
        case .borderSubtle:
            switch scheme {
            case .light:
                return LunaraColorToken(red: 0.573, green: 0.647, blue: 0.431, opacity: 0.52)
            case .dark:
                return LunaraColorToken(red: 0.686, green: 0.729, blue: 0.518, opacity: 0.58)
            @unknown default:
                return LunaraColorToken(red: 0.573, green: 0.647, blue: 0.431, opacity: 0.52)
            }
        }
    }

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
