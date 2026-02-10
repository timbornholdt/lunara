import SwiftUI
import UIKit

struct AlbumTheme: Equatable {
    let backgroundTop: Color
    let backgroundBottom: Color
    let textPrimary: Color
    let textSecondary: Color
    let accentPrimary: Color
    let accentSecondary: Color
    let raised: Color
    let borderSubtle: Color
    let baseUIColor: UIColor
    let linenLineUIColor: UIColor

    static func from(_ theme: ArtworkTheme) -> AlbumTheme {
        AlbumTheme(
            backgroundTop: Color(uiColor: theme.backgroundTop),
            backgroundBottom: Color(uiColor: theme.backgroundBottom),
            textPrimary: Color(uiColor: theme.textPrimary),
            textSecondary: Color(uiColor: theme.textSecondary),
            accentPrimary: Color(uiColor: theme.accentPrimary),
            accentSecondary: Color(uiColor: theme.accentSecondary),
            raised: Color(uiColor: theme.raised),
            borderSubtle: Color(uiColor: theme.borderSubtle),
            baseUIColor: theme.backgroundTop,
            linenLineUIColor: theme.linenLine
        )
    }

    static func fallback() -> AlbumTheme {
        let palette = LunaraTheme.Palette.colors(for: .light)
        return AlbumTheme(
            backgroundTop: palette.base,
            backgroundBottom: palette.raised,
            textPrimary: palette.textPrimary,
            textSecondary: palette.textSecondary,
            accentPrimary: palette.accentPrimary,
            accentSecondary: palette.accentSecondary,
            raised: palette.raised,
            borderSubtle: palette.borderSubtle,
            baseUIColor: palette.baseUIColor,
            linenLineUIColor: palette.linenLineUIColor
        )
    }
}

protocol ArtworkThemeProviding {
    func theme(for request: ArtworkRequest?) async -> AlbumTheme?
}

final class ArtworkThemeProvider: ArtworkThemeProviding {
    static let shared = ArtworkThemeProvider()

    private let loader: ArtworkLoader
    private var cache: [String: AlbumTheme] = [:]

    init(loader: ArtworkLoader = .shared) {
        self.loader = loader
    }

    func theme(for request: ArtworkRequest?) async -> AlbumTheme? {
        guard let request else { return nil }
        let key = request.key.cacheKeyString
        if let cached = cache[key] {
            return cached
        }
        guard let image = try? await loader.loadImage(for: request.key, url: request.url),
              let artworkTheme = ArtworkThemeExtractor.extractTheme(from: image) else {
            return nil
        }
        let theme = AlbumTheme.from(artworkTheme)
        cache[key] = theme
        return theme
    }
}
