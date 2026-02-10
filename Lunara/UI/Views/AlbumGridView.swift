import SwiftUI

struct AlbumGridView: View {
    let albums: [PlexAlbum]
    let palette: LunaraTheme.PaletteColors
    let playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    let ratingKeys: (PlexAlbum) -> [String]

    enum Layout {
        static let globalPadding = LunaraTheme.Layout.globalPadding
        static let columnSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 18
        static let cardCornerRadius = LunaraTheme.Layout.cardCornerRadius
        static let cardShadowOpacity: Double = 0.08
        static let cardShadowRadius: CGFloat = 8
        static let cardShadowYOffset: CGFloat = 1
        static let titleHeight: CGFloat = 40
        static let yearHeight: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let verticalSpacing: CGFloat = 16

        static func cardHeight(for width: CGFloat) -> CGFloat {
            width + titleHeight + yearHeight + verticalPadding + verticalSpacing
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - (Layout.globalPadding * 2), 0)
            let columnWidth = max((contentWidth - Layout.columnSpacing) / 2, 0)
            let columns = [
                GridItem(.fixed(columnWidth), spacing: Layout.columnSpacing),
                GridItem(.fixed(columnWidth), spacing: Layout.columnSpacing)
            ]

            ScrollView {
                LazyVGrid(columns: columns, spacing: Layout.rowSpacing) {
                    ForEach(albums, id: \.dedupIdentity) { album in
                        NavigationLink {
                            AlbumDetailView(
                                album: album,
                                albumRatingKeys: ratingKeys(album),
                                playbackViewModel: playbackViewModel,
                                sessionInvalidationHandler: signOut
                            )
                        } label: {
                            AlbumCardView(album: album, palette: palette, width: columnWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Layout.globalPadding)
            }
        }
    }
}

private struct AlbumCardView: View {
    let album: PlexAlbum
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumArtworkView(album: album, palette: palette)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: AlbumGridView.Layout.cardCornerRadius))
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(LunaraTheme.Typography.displayBold(size: 15))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Text(metadataText)
                    .font(LunaraTheme.Typography.display(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .opacity(metadataText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: width, height: AlbumGridView.Layout.cardHeight(for: width), alignment: .top)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: AlbumGridView.Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AlbumGridView.Layout.cardCornerRadius))
        .shadow(
            color: Color.black.opacity(AlbumGridView.Layout.cardShadowOpacity),
            radius: AlbumGridView.Layout.cardShadowRadius,
            x: 0,
            y: AlbumGridView.Layout.cardShadowYOffset
        )
    }

    private var metadataText: String {
        let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = album.year.map(String.init)
        switch (artist?.isEmpty == false ? artist : nil, year) {
        case let (.some(name), .some(yearValue)):
            return "\(name) — \(yearValue)"
        case let (.some(name), .none):
            return name
        case let (.none, .some(yearValue)):
            return yearValue
        default:
            return " "
        }
    }
}

struct AlbumArtworkView: View {
    let album: PlexAlbum
    let palette: LunaraTheme.PaletteColors?

    init(album: PlexAlbum, palette: LunaraTheme.PaletteColors? = nil) {
        self.album = album
        self.palette = palette
    }

    var body: some View {
        let placeholder = palette?.raised ?? Color.gray.opacity(0.2)
        let secondaryText = palette?.textSecondary ?? Color.secondary

        if let url = artworkURL() {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        placeholder
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                case .failure:
                    placeholder
                        .overlay(Text("No Art").font(.caption).foregroundStyle(secondaryText))
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
                .overlay(Text("No Art").font(.caption).foregroundStyle(secondaryText))
        }
    }

    private func artworkURL() -> URL? {
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = PlexArtworkURLBuilder(baseURL: baseURL, token: token, maxSize: PlexDefaults.maxArtworkSize)
        let resolver = AlbumArtworkResolver(artworkBuilder: builder)
        return resolver.artworkURL(for: album)
    }
}
