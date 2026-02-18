import SwiftUI

extension Color {
    static func lunara(_ role: LunaraSemanticColorRole) -> Color {
        let token = LunaraVisualTokens.colorToken(for: role)
        return Color(
            .sRGB,
            red: token.red,
            green: token.green,
            blue: token.blue,
            opacity: token.opacity
        )
    }
}
