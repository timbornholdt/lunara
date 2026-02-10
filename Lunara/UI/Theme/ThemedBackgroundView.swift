import SwiftUI

struct ThemedBackgroundView: View {
    let theme: AlbumTheme
    let seed: UInt64
    let tileSize: CGFloat

    init(theme: AlbumTheme, seed: UInt64 = 42, tileSize: CGFloat = 96) {
        self.theme = theme
        self.seed = seed
        self.tileSize = tileSize
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.backgroundTop, theme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let tile = LinenTextureGenerator.tileImage(
                size: CGSize(width: tileSize, height: tileSize),
                base: theme.baseUIColor,
                line: theme.linenLineUIColor,
                seed: seed
            ) {
                Image(decorative: tile, scale: 1)
                    .resizable(resizingMode: .tile)
                    .opacity(0.06)
                    .blendMode(.multiply)
            }
        }
        .ignoresSafeArea()
    }
}
