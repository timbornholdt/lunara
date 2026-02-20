import SwiftUI

struct ArtworkPaletteTheme: Equatable {
    let background: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color

    static let `default` = ArtworkPaletteTheme(
        background: Color.lunara(.backgroundBase),
        textPrimary: Color.lunara(.textPrimary),
        textSecondary: Color.lunara(.textSecondary),
        accent: Color.lunara(.accentPrimary)
    )
}
