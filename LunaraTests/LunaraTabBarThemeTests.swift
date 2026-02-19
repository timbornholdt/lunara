import Testing
@testable import Lunara

struct LunaraTabBarThemeTests {
    @Test
    func gardenTheme_matchesLunaraVisualPaletteRoles() {
        let theme = LunaraTabBarTheme.garden

        #expect(theme.selectedTintRole == .accentPrimary)
        #expect(theme.unselectedTintRole == .textSecondary)
        #expect(theme.backgroundRole == .backgroundBase)
        #expect(theme.borderRole == .borderSubtle)
    }

    @Test
    func customTheme_canOverrideEachRole() {
        let theme = LunaraTabBarTheme(
            selectedTintRole: .textPrimary,
            unselectedTintRole: .accentOnAccent,
            backgroundRole: .backgroundElevated,
            borderRole: .accentPrimary
        )

        #expect(theme.selectedTintRole == .textPrimary)
        #expect(theme.unselectedTintRole == .accentOnAccent)
        #expect(theme.backgroundRole == .backgroundElevated)
        #expect(theme.borderRole == .accentPrimary)
    }
}
