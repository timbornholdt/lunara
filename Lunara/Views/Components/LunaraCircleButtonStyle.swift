import SwiftUI

/// Circular icon-only sibling of LunaraPillButtonStyle, sharing its color
/// tokens — for compact headers where "Play All"/"Shuffle" become icons
/// (Lunara-1mu). Callers must attach an accessibilityLabel.
struct LunaraCircleButtonStyle: ButtonStyle {
    let role: LunaraPillButtonRole

    init(role: LunaraPillButtonRole = .primary) {
        self.role = role
    }

    func makeBody(configuration: Configuration) -> some View {
        let token = LunaraVisualTokens.pillButtonToken(for: role)

        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.lunara(token.foregroundRole))
            .frame(width: 44, height: 44)
            .background {
                Circle()
                    .fill(Color.lunara(token.backgroundRole))
                    .overlay {
                        if let borderRole = token.borderRole {
                            Circle()
                                .stroke(Color.lunara(borderRole), lineWidth: 1)
                        }
                    }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
