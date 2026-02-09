import SwiftUI
import Testing
@testable import Lunara

struct LunaraThemeTests {
    @Test func layoutConstantsMatchSpec() {
        #expect(LunaraTheme.Layout.globalPadding == 20)
        #expect(LunaraTheme.Layout.sectionSpacing == 20)
        #expect(LunaraTheme.Layout.primaryButtonHeight == 52)
        #expect(LunaraTheme.Layout.cardCornerRadius == 12)
    }

    @Test func typographyUsesPlayfairDisplay() {
        #expect(LunaraTheme.Typography.displayFontName == "PlayfairDisplay-SemiBold")
        #expect(LunaraTheme.Typography.displayItalicFontName == "PlayfairDisplay-Italic")
        #expect(LunaraTheme.Typography.displayBoldFontName == "PlayfairDisplay-Bold")
    }

    @Test func lightAndDarkPalettesDiffer() {
        let light = LunaraTheme.Palette.colors(for: .light)
        let dark = LunaraTheme.Palette.colors(for: .dark)

        #expect(light.base != dark.base)
        #expect(light.textPrimary != dark.textPrimary)
        #expect(light.accentPrimary != dark.accentPrimary)
    }

    @Test func signInViewUsesThemeLayout() {
        #expect(SignInView.Layout.globalPadding == LunaraTheme.Layout.globalPadding)
        #expect(SignInView.Layout.primaryButtonHeight == LunaraTheme.Layout.primaryButtonHeight)
        #expect(SignInView.Layout.cardCornerRadius == LunaraTheme.Layout.cardCornerRadius)
    }
}
