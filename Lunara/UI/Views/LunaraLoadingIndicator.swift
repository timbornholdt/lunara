import SwiftUI

struct LunaraLoadingIndicator: View {
    let palette: LunaraTheme.PaletteColors
    @State private var phase: Double = 0

    private let size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.raised.opacity(0.9))
                .overlay(
                    Circle()
                        .stroke(palette.borderSubtle.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)

            Circle()
                .trim(from: 0.05, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            palette.textPrimary.opacity(0.05),
                            palette.textPrimary.opacity(0.7),
                            palette.textPrimary
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(phase * 360))
                .shadow(color: palette.textPrimary.opacity(0.25), radius: 6, x: 0, y: 0)

            orbitingDot(angle: phase * 360)
            orbitingDot(angle: phase * 360 + 130, scale: 0.7, opacity: 0.7)
            orbitingDot(angle: phase * 360 + 260, scale: 0.55, opacity: 0.5)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .onDisappear {
            phase = 0
        }
        .accessibilityLabel("Refreshing")
    }

    private func orbitingDot(angle: Double, scale: CGFloat = 1, opacity: Double = 1) -> some View {
        Circle()
            .fill(palette.textPrimary.opacity(0.9))
            .frame(width: 4, height: 4)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: -size * 0.36)
            .rotationEffect(.degrees(angle))
            .shadow(color: palette.textPrimary.opacity(0.3), radius: 3, x: 0, y: 0)
    }
}
