import SwiftUI

private struct LunaraLinenOverlay: View {
    var body: some View {
        let token = LunaraVisualTokens.linenToken
        // Canvas sizes the weave from the actual geometry — fixed line counts
        // left untextured strips on wide screens (Lunara-9ws).
        Canvas { context, size in
            let lineColor = Color.lunara(.accentOnAccent)
            let lineWidth: CGFloat = 0.5

            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                let opacity = row.isMultiple(of: 2) ? token.horizontalOpacity : token.horizontalOpacity * 0.3
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: lineWidth)),
                    with: .color(lineColor.opacity(opacity))
                )
                y += lineWidth + token.horizontalLineSpacing
                row += 1
            }

            var x: CGFloat = 0
            var column = 0
            while x < size.width {
                let opacity = column.isMultiple(of: 3) ? token.verticalOpacity : token.verticalOpacity * 0.25
                context.fill(
                    Path(CGRect(x: x, y: 0, width: lineWidth, height: size.height)),
                    with: .color(lineColor.opacity(opacity))
                )
                x += lineWidth + token.verticalLineSpacing
                column += 1
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
