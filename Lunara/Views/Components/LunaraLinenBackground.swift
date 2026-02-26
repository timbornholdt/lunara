import SwiftUI

private struct LunaraLinenOverlay: View {
    var body: some View {
        let token = LunaraVisualTokens.linenToken
        VStack(spacing: token.horizontalLineSpacing) {
            ForEach(0..<160, id: \.self) { index in
                Rectangle()
                    .fill(.white.opacity(index.isMultiple(of: 2) ? token.horizontalOpacity : token.horizontalOpacity * 0.3))
                    .frame(height: 0.5)
            }
        }
        .overlay {
            HStack(spacing: token.verticalLineSpacing) {
                ForEach(0..<100, id: \.self) { index in
                    Rectangle()
                        .fill(.white.opacity(index.isMultiple(of: 3) ? token.verticalOpacity : token.verticalOpacity * 0.25))
                        .frame(width: 0.5)
                }
            }
        }
        .blendMode(.overlay)
        .opacity(0.9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LunaraLinenBackgroundModifier: ViewModifier {
    let role: LunaraSemanticColorRole

    func body(content: Content) -> some View {
        content
            .background {
                Color.lunara(role)
                    .overlay {
                        LunaraLinenOverlay()
                    }
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func lunaraLinenBackground(role: LunaraSemanticColorRole = .backgroundBase) -> some View {
        modifier(LunaraLinenBackgroundModifier(role: role))
    }
}
