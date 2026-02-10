import SwiftUI

struct InitialScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Layout {
        static let emblemSize: CGFloat = 120
        static let emblemInnerSize: CGFloat = 64
        static let emblemRingWidth: CGFloat = 2
        static let stackSpacing: CGFloat = 18
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        ZStack {
            LinenBackgroundView(palette: palette)
            VStack(spacing: Layout.stackSpacing) {
                emblem(palette: palette)
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

    private func emblem(palette: LunaraTheme.PaletteColors) -> some View {
        ZStack {
            Circle()
                .fill(palette.raised)
                .shadow(color: palette.borderSubtle.opacity(0.5), radius: 10, x: 0, y: 4)
            Circle()
                .stroke(palette.borderSubtle, lineWidth: Layout.emblemRingWidth)
            Circle()
                .fill(palette.accentPrimary.opacity(0.15))
                .frame(width: Layout.emblemInnerSize, height: Layout.emblemInnerSize)
            Circle()
                .stroke(palette.accentPrimary, lineWidth: 1)
                .frame(width: Layout.emblemInnerSize - 10, height: Layout.emblemInnerSize - 10)
        }
        .frame(width: Layout.emblemSize, height: Layout.emblemSize)
    }
}

#Preview {
    InitialScreenView()
}
