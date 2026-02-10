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
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - (Layout.globalPadding * 2), 0)
            let columnWidth = max((contentWidth - Layout.columnSpacing) / 2, 0)
            let rows = AlbumGridView.makeRows(from: albums)

            ScrollView {
                LazyVStack(spacing: Layout.rowSpacing) {
                    ForEach(rows) { row in
                        AlbumRowView(
                            row: row,
                            palette: palette,
                            width: columnWidth,
                            playbackViewModel: playbackViewModel,
                            signOut: signOut,
                            ratingKeys: ratingKeys
                        )
                    }
                }
                .padding(Layout.globalPadding)
            }
        }
    }

    private static func makeRows(from albums: [PlexAlbum]) -> [AlbumRow] {
        var rows: [AlbumRow] = []
        rows.reserveCapacity((albums.count + 1) / 2)

        var index = 0
        while index < albums.count {
            let left = albums[index]
            let right = index + 1 < albums.count ? albums[index + 1] : nil
            rows.append(AlbumRow(id: index, left: left, right: right))
            index += 2
        }

        return rows
    }
}

private struct AlbumRow: Identifiable {
    let id: Int
    let left: PlexAlbum
    let right: PlexAlbum?
}

private struct AlbumRowView: View {
    let row: AlbumRow
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat
    let playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    let ratingKeys: (PlexAlbum) -> [String]

    @State private var leftHeight: CGFloat = 0
    @State private var rightHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: AlbumGridView.Layout.columnSpacing) {
            card(for: row.left, height: maxHeight, measuredHeight: $leftHeight)

            if let right = row.right {
                card(for: right, height: maxHeight, measuredHeight: $rightHeight)
            } else {
                Color.clear
                    .frame(width: width)
            }
        }
    }

    private var maxHeight: CGFloat {
        max(leftHeight, rightHeight)
    }

    private func card(for album: PlexAlbum, height: CGFloat, measuredHeight: Binding<CGFloat>) -> some View {
        NavigationLink {
            AlbumDetailView(
                album: album,
                albumRatingKeys: ratingKeys(album),
                playbackViewModel: playbackViewModel,
                sessionInvalidationHandler: signOut
            )
        } label: {
            AlbumCardView(
                album: album,
                palette: palette,
                width: width,
                height: height > 0 ? height : nil,
                onHeightChange: { measuredHeight.wrappedValue = $0 }
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumCardView: View {
    let album: PlexAlbum
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat
    let height: CGFloat?
    let onHeightChange: (CGFloat) -> Void

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
        .readHeight(onHeightChange)
        .frame(width: width, alignment: .top)
        .frame(height: height, alignment: .top)
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

private struct HeightReaderKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightReaderKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightReaderKey.self, perform: onChange)
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
