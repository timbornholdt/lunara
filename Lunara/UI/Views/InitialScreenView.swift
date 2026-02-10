import SwiftUI

struct InitialScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Layout {
        static let stackSpacing: CGFloat = 18
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        ZStack {
            LinenBackgroundView(palette: palette)
            TrianglePatternView(palette: palette)
            VStack(spacing: Layout.stackSpacing) {
                Text("Lunara")
                    .font(LunaraTheme.Typography.display(size: 36))
                    .foregroundStyle(palette.textPrimary)
                ProgressView()
                    .tint(palette.accentPrimary)
            }
            .padding(.horizontal, LunaraTheme.Layout.globalPadding)
        }
        .ignoresSafeArea()
    }
}

private struct TrianglePatternView: View {
    let palette: LunaraTheme.PaletteColors
    @State private var seed: UInt64 = .random(in: 0...UInt64.max)

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let columns = max(6, Int(size.width / 48))
                let triangleWidth = size.width / CGFloat(columns)
                let triangleHeight = triangleWidth * 0.9
                let rows = max(6, Int((size.height * 0.6) / triangleHeight) + 2)
                var rng = SeededGenerator(seed: seed)
                let fills = [
                    palette.accentPrimary.opacity(0.18),
                    palette.accentPrimary.opacity(0.08),
                    palette.accentSecondary.opacity(0.2),
                    palette.accentSecondary.opacity(0.1),
                    palette.borderSubtle.opacity(0.35),
                    palette.textPrimary.opacity(0.06)
                ]

                for row in 0..<rows {
                    for column in 0..<columns {
                        let originX = CGFloat(column) * triangleWidth
                        let originY = CGFloat(row) * triangleHeight * 0.88
                        let isPointingDown = (row + column) % 2 == 0
                        let path = trianglePath(
                            originX: originX,
                            originY: originY,
                            width: triangleWidth,
                            height: triangleHeight,
                            pointingDown: isPointingDown
                        )
                        let color = fills[Int(rng.next() % UInt64(fills.count))]
                        context.fill(path, with: .color(color))
                    }
                }
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.5),
                        .init(color: .clear, location: 0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
        }
        .onAppear {
            seed = .random(in: 0...UInt64.max)
        }
    }

    private func trianglePath(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        pointingDown: Bool
    ) -> Path {
        Path { path in
            if pointingDown {
                path.move(to: CGPoint(x: originX, y: originY))
                path.addLine(to: CGPoint(x: originX + width, y: originY))
                path.addLine(to: CGPoint(x: originX + width * 0.5, y: originY + height))
            } else {
                path.move(to: CGPoint(x: originX, y: originY + height))
                path.addLine(to: CGPoint(x: originX + width, y: originY + height))
                path.addLine(to: CGPoint(x: originX + width * 0.5, y: originY))
            }
            path.closeSubpath()
        }
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}

#Preview {
    InitialScreenView()
}
