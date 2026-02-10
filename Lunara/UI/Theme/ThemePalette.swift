import SwiftUI
import UIKit

struct ThemePalette: Equatable {
    let base: Color
    let raised: Color
    let textPrimary: Color
    let textSecondary: Color
    let accentPrimary: Color
    let accentSecondary: Color
    let borderSubtle: Color
    let baseUIColor: UIColor
    let linenLineUIColor: UIColor
}

extension ThemePalette {
    init(palette: LunaraTheme.PaletteColors) {
        self.base = palette.base
        self.raised = palette.raised
        self.textPrimary = palette.textPrimary
        self.textSecondary = palette.textSecondary
        self.accentPrimary = palette.accentPrimary
        self.accentSecondary = palette.accentSecondary
        self.borderSubtle = palette.borderSubtle
        self.baseUIColor = palette.baseUIColor
        self.linenLineUIColor = palette.linenLineUIColor
    }

    init(theme: AlbumTheme) {
        self.base = theme.backgroundTop
        self.raised = theme.raised
        self.textPrimary = theme.textPrimary
        self.textSecondary = theme.textSecondary
        self.accentPrimary = theme.accentPrimary
        self.accentSecondary = theme.accentSecondary
        self.borderSubtle = theme.borderSubtle
        self.baseUIColor = theme.baseUIColor
        self.linenLineUIColor = theme.linenLineUIColor
    }
}
