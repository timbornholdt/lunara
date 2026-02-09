import SwiftUI

struct LunaraPrimaryButtonStyle: ButtonStyle {
    let palette: LunaraTheme.PaletteColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: LunaraTheme.Layout.primaryButtonHeight)
            .foregroundStyle(Color.white)
            .background(palette.accentPrimary.opacity(configuration.isPressed ? 0.9 : 1.0))
            .clipShape(Capsule())
    }
}

struct LunaraSecondaryButtonStyle: ButtonStyle {
    let palette: LunaraTheme.PaletteColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: LunaraTheme.Layout.primaryButtonHeight)
            .foregroundStyle(palette.accentPrimary)
            .background(palette.raised.opacity(configuration.isPressed ? 0.96 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
    }
}

