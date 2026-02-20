import Testing
@testable import Lunara

struct LunaraTabBarThemeTests {
    @Test
    func gardenTheme_matchesLunaraVisualPaletteRoles() {
        let theme = LunaraTabBarTheme.garden

        #expect(theme.selectedTintRole == .accentPrimary)
        #expect(theme.unselectedTintRole == .textSecondary)
    }

    @Test
    func customTheme_canOverrideEachRole() {
        let theme = LunaraTabBarTheme(
            selectedTintRole: .textPrimary,
            unselectedTintRole: .accentOnAccent
        )

        #expect(theme.selectedTintRole == .textPrimary)
        #expect(theme.unselectedTintRole == .accentOnAccent)
    }
}
