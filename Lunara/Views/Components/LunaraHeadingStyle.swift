import SwiftUI
import UIKit

private struct LunaraHeadingModifier: ViewModifier {
    let level: LunaraHeadingLevel
    let weight: LunaraHeadingWeight

    func body(content: Content) -> some View {
        let token = LunaraVisualTokens.headingToken(for: level, weight: weight)
        content
            .font(font(for: token))
            .foregroundStyle(Color.lunara(.textPrimary))
    }

    private func font(for token: LunaraHeadingToken) -> Font {
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(
                token.preferredFontName,
                size: token.size,
                relativeTo: token.relativeTextStyle
            )
        }

        return .system(
            size: token.size,
            weight: token.fallbackWeight,
            design: .serif
        )
    }
}

extension View {
    func lunaraHeading(
        _ level: LunaraHeadingLevel = .title,
        weight: LunaraHeadingWeight = .regular
    ) -> some View {
        modifier(LunaraHeadingModifier(level: level, weight: weight))
    }
}
