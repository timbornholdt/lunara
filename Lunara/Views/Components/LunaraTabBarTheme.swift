import SwiftUI
import UIKit

struct LunaraTabBarTheme: Equatable {
    let selectedTintRole: LunaraSemanticColorRole
    let unselectedTintRole: LunaraSemanticColorRole
    let backgroundRole: LunaraSemanticColorRole
    let borderRole: LunaraSemanticColorRole

    static let garden = LunaraTabBarTheme(
        selectedTintRole: .accentPrimary,
        unselectedTintRole: .textSecondary,
        backgroundRole: .backgroundBase,
        borderRole: .borderSubtle
    )
}

@MainActor
enum LunaraTabBarStyler {
    static func apply(theme: LunaraTabBarTheme) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.lunara(theme.backgroundRole)
        appearance.shadowColor = UIColor.lunara(theme.borderRole)

        let font = tabLabelFont()
        applyAttributes(
            to: appearance.stackedLayoutAppearance,
            selectedColor: UIColor.lunara(theme.selectedTintRole),
            unselectedColor: UIColor.lunara(theme.unselectedTintRole),
            font: font
        )
        applyAttributes(
            to: appearance.inlineLayoutAppearance,
            selectedColor: UIColor.lunara(theme.selectedTintRole),
            unselectedColor: UIColor.lunara(theme.unselectedTintRole),
            font: font
        )
        applyAttributes(
            to: appearance.compactInlineLayoutAppearance,
            selectedColor: UIColor.lunara(theme.selectedTintRole),
            unselectedColor: UIColor.lunara(theme.unselectedTintRole),
            font: font
        )

        let tabBarAppearance = UITabBar.appearance()
        tabBarAppearance.standardAppearance = appearance
        tabBarAppearance.scrollEdgeAppearance = appearance
        tabBarAppearance.tintColor = UIColor.lunara(theme.selectedTintRole)
        tabBarAppearance.unselectedItemTintColor = UIColor.lunara(theme.unselectedTintRole)
    }

    private static func applyAttributes(
        to layoutAppearance: UITabBarItemAppearance,
        selectedColor: UIColor,
        unselectedColor: UIColor,
        font: UIFont
    ) {
        layoutAppearance.selected.iconColor = selectedColor
        layoutAppearance.normal.iconColor = unselectedColor
        layoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor, .font: font]
        layoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselectedColor, .font: font]
    }

    private static func tabLabelFont() -> UIFont {
        let size: CGFloat = 13
        if let customFont = UIFont(name: "PlayfairDisplay-SemiBold", size: size) {
            return customFont
        }

        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }
}
