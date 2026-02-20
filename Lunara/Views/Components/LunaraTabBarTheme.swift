import SwiftUI

struct LunaraTabBarTheme: Equatable {
    let selectedTintRole: LunaraSemanticColorRole
    let unselectedTintRole: LunaraSemanticColorRole

    static let garden = LunaraTabBarTheme(
        selectedTintRole: .accentPrimary,
        unselectedTintRole: .textSecondary
    )
}
