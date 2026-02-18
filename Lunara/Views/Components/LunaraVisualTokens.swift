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
    static func colorToken(for role: LunaraSemanticColorRole) -> LunaraColorToken {
        switch role {
        case .backgroundBase:
            return LunaraColorToken(red: 0.964, green: 0.941, blue: 0.886, opacity: 1.0)
        case .backgroundElevated:
            return LunaraColorToken(red: 0.987, green: 0.972, blue: 0.932, opacity: 1.0)
        case .textPrimary:
            return LunaraColorToken(red: 0.165, green: 0.153, blue: 0.129, opacity: 1.0)
        case .textSecondary:
            return LunaraColorToken(red: 0.388, green: 0.365, blue: 0.318, opacity: 1.0)
        case .accentPrimary:
            return LunaraColorToken(red: 0.341, green: 0.235, blue: 0.165, opacity: 1.0)
        case .accentOnAccent:
            return LunaraColorToken(red: 0.996, green: 0.985, blue: 0.957, opacity: 1.0)
        case .borderSubtle:
            return LunaraColorToken(red: 0.712, green: 0.653, blue: 0.557, opacity: 0.58)
        }
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
