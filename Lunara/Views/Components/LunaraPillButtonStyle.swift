import SwiftUI

struct LunaraPillButtonStyle: ButtonStyle {
    let role: LunaraPillButtonRole

    init(role: LunaraPillButtonRole = .primary) {
        self.role = role
    }

    func makeBody(configuration: Configuration) -> some View {
        let token = LunaraVisualTokens.pillButtonToken(for: role)

        return configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.lunara(token.foregroundRole))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.lunara(token.backgroundRole))
                    .overlay {
                        if let borderRole = token.borderRole {
                            Capsule(style: .continuous)
                                .stroke(Color.lunara(borderRole), lineWidth: 1)
                        }
                    }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
