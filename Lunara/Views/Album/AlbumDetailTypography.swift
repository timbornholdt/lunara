import SwiftUI
import UIKit

enum AlbumDetailTextRole {
    case subtitleMetadata
    case trackNumber
    case trackTitle
    case trackSecondaryArtist
    case trackDuration
    case reviewBody
    case pill
}

struct AlbumDetailTextToken: Equatable {
    let preferredFontName: String
    let fallbackWeight: Font.Weight
    let size: CGFloat
    let relativeTextStyle: Font.TextStyle
    let usesMonospacedDigits: Bool
}

enum AlbumDetailTypography {
    static func token(for role: AlbumDetailTextRole) -> AlbumDetailTextToken {
        switch role {
        case .subtitleMetadata:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-Regular",
                fallbackWeight: .regular,
                size: 17,
                relativeTextStyle: .subheadline,
                usesMonospacedDigits: false
            )
        case .trackNumber:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-SemiBold",
                fallbackWeight: .semibold,
                size: 18,
                relativeTextStyle: .body,
                usesMonospacedDigits: true
            )
        case .trackTitle:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-Regular",
                fallbackWeight: .regular,
                size: 20,
                relativeTextStyle: .body,
                usesMonospacedDigits: false
            )
        case .trackSecondaryArtist:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-Regular",
                fallbackWeight: .regular,
                size: 18,
                relativeTextStyle: .subheadline,
                usesMonospacedDigits: false
            )
        case .trackDuration:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-Regular",
                fallbackWeight: .regular,
                size: 16,
                relativeTextStyle: .footnote,
                usesMonospacedDigits: true
            )
        case .reviewBody:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-Regular",
                fallbackWeight: .regular,
                size: 18,
                relativeTextStyle: .body,
                usesMonospacedDigits: false
            )
        case .pill:
            return AlbumDetailTextToken(
                preferredFontName: "PlayfairDisplay-SemiBold",
                fallbackWeight: .semibold,
                size: 14,
                relativeTextStyle: .caption,
                usesMonospacedDigits: false
            )
        }
    }

    static func font(for role: AlbumDetailTextRole) -> Font {
        let token = token(for: role)
        let baseFont: Font
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            baseFont = .custom(
                token.preferredFontName,
                size: token.size,
                relativeTo: token.relativeTextStyle
            )
        } else {
            baseFont = .system(
                size: token.size,
                weight: token.fallbackWeight,
                design: .serif
            )
        }

        if token.usesMonospacedDigits {
            return baseFont.monospacedDigit()
        }
        return baseFont
    }
}
