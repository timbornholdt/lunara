import SwiftUI
import UIKit

enum LunaraTheme {
    enum Layout {
        static let globalPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 20
        static let primaryButtonHeight: CGFloat = 52
        static let cardCornerRadius: CGFloat = 12
        static let cardHorizontalPadding: CGFloat = 14
    }

    enum Typography {
        static let displayFontName = "PlayfairDisplay-SemiBold"
        static let displayItalicFontName = "PlayfairDisplay-Italic"
        static let displayBoldFontName = "PlayfairDisplay-Bold"
        static let displayRegularFontName = "PlayfairDisplay-Regular"

        static func display(size: CGFloat) -> Font {
            .custom(displayFontName, size: size)
        }

        static func displayRegular(size: CGFloat) -> Font {
            .custom(displayRegularFontName, size: size)
        }

        static func displayBold(size: CGFloat) -> Font {
            .custom(displayBoldFontName, size: size)
        }
    }

    struct PaletteColors: Equatable {
        let base: Color
        let raised: Color
        let textPrimary: Color
        let textSecondary: Color
        let accentPrimary: Color
        let accentSecondary: Color
        let borderSubtle: Color
        let stateError: Color
        let stateSuccess: Color
        let baseUIColor: UIColor
        let linenLineUIColor: UIColor
    }

    enum Palette {
        static func colors(for colorScheme: ColorScheme) -> PaletteColors {
            colorScheme == .dark ? dark : light
        }

        private static let light = PaletteColors(
            base: Color(hex: 0xF6F1EA),
            raised: Color(hex: 0xFFFCF7),
            textPrimary: Color(hex: 0x1A1A18),
            textSecondary: Color(hex: 0x5B5A55),
            accentPrimary: Color(hex: 0x3D5A4A),
            accentSecondary: Color(hex: 0xC9A23A),
            borderSubtle: Color(hex: 0xE4DED5),
            stateError: Color(hex: 0xB33A3A),
            stateSuccess: Color(hex: 0x2E6B4E),
            baseUIColor: UIColor(hex: 0xF6F1EA),
            linenLineUIColor: UIColor(hex: 0xE4DED5)
        )

        private static let dark = PaletteColors(
            base: Color(hex: 0x14110D),
            raised: Color(hex: 0x1C1813),
            textPrimary: Color(hex: 0xF2ECE3),
            textSecondary: Color(hex: 0xC7C0B6),
            accentPrimary: Color(hex: 0x6E8A78),
            accentSecondary: Color(hex: 0xC9A23A),
            borderSubtle: Color(hex: 0x2A241D),
            stateError: Color(hex: 0xD36A6A),
            stateSuccess: Color(hex: 0x4C8B65),
            baseUIColor: UIColor(hex: 0x14110D),
            linenLineUIColor: UIColor(hex: 0x2A241D)
        )
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
