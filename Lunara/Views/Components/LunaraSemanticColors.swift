import SwiftUI
import UIKit

extension Color {
    static func lunara(_ role: LunaraSemanticColorRole) -> Color {
        Color(
            uiColor: UIColor { traits in
                let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
                return UIColor(token: LunaraVisualTokens.colorToken(for: role, in: scheme))
            }
        )
    }
}

private extension UIColor {
    convenience init(token: LunaraColorToken) {
        self.init(
            red: token.red,
            green: token.green,
            blue: token.blue,
            alpha: token.opacity
        )
    }
}
