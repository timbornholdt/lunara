import Foundation
import SwiftUI
import Testing
@testable import Lunara

struct LunaraVisualTokensTests {
    @Test
    func colorToken_backgroundBaseLight_matchesExpectedRGBA() {
        let token = LunaraVisualTokens.colorToken(for: .backgroundBase, in: .light)

        #expect(token == LunaraColorToken(red: 0.933, green: 0.953, blue: 0.976, opacity: 1.0))
    }

    @Test
    func colorToken_backgroundBaseDark_matchesExpectedRGBA() {
        let token = LunaraVisualTokens.colorToken(for: .backgroundBase, in: .dark)

        #expect(token == LunaraColorToken(red: 0.000, green: 0.106, blue: 0.180, opacity: 1.0))
    }

    @Test
    func colorToken_accentPrimaryDark_matchesExpectedRGBA() {
        let token = LunaraVisualTokens.colorToken(for: .accentPrimary, in: .dark)

        #expect(token == LunaraColorToken(red: 0.702, green: 0.804, blue: 0.894, opacity: 1.0))
    }

    @Test
    func colorToken_borderSubtleLight_hasPartialOpacity() {
        let token = LunaraVisualTokens.colorToken(for: .borderSubtle, in: .light)

        #expect(token == LunaraColorToken(red: 0.325, green: 0.463, blue: 0.573, opacity: 0.3))
    }

    @Test
    func headingToken_displaySemibold_mapsToPlayfairSemiboldAndLargeTitleScale() {
        let token = LunaraVisualTokens.headingToken(for: .display, weight: .semibold)

        #expect(token.preferredFontName == "PlayfairDisplay-SemiBold")
        #expect(token.fallbackWeight == .semibold)
        #expect(token.size == 40)
        #expect(token.relativeTextStyle == .largeTitle)
    }

    @Test
    func headingToken_sectionRegular_mapsToPlayfairRegularAndTitle3Scale() {
        let token = LunaraVisualTokens.headingToken(for: .section, weight: .regular)

        #expect(token.preferredFontName == "PlayfairDisplay-Regular")
        #expect(token.fallbackWeight == .regular)
        #expect(token.size == 22)
        #expect(token.relativeTextStyle == .title3)
    }

    @Test
    func pillButtonToken_secondary_usesElevatedBackgroundAndBorder() {
        let token = LunaraVisualTokens.pillButtonToken(for: .secondary)

        #expect(token.backgroundRole == .backgroundElevated)
        #expect(token.foregroundRole == .textPrimary)
        #expect(token.borderRole == .borderSubtle)
    }

    @Test
    func linenToken_usesStableTextureValues() {
        let token = LunaraVisualTokens.linenToken

        #expect(token == LunaraLinenToken(horizontalOpacity: 0.18, verticalOpacity: 0.12, horizontalLineSpacing: 3, verticalLineSpacing: 4))
    }
}
