import Foundation
import SwiftUI
import Testing
@testable import Lunara

struct LunaraVisualTokensTests {
    @Test
    func colorToken_backgroundBase_matchesExpectedRGBA() {
        let token = LunaraVisualTokens.colorToken(for: .backgroundBase)

        #expect(token == LunaraColorToken(red: 0.964, green: 0.941, blue: 0.886, opacity: 1.0))
    }

    @Test
    func colorToken_borderSubtle_hasPartialOpacity() {
        let token = LunaraVisualTokens.colorToken(for: .borderSubtle)

        #expect(token == LunaraColorToken(red: 0.712, green: 0.653, blue: 0.557, opacity: 0.58))
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
