import SwiftUI

struct GenrePillView: View {
    let title: String
    let palette: ThemePalette

    var body: some View {
        Text(title)
            .font(LunaraTheme.Typography.displayRegular(size: 12))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(palette.raised)
            .overlay(
                Capsule()
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
