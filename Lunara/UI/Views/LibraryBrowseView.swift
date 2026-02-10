import SwiftUI

struct LibraryBrowseView: View {
    @StateObject var viewModel: LibraryViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme

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
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        NavigationStack {
            ZStack {
                LinenBackgroundView(palette: palette)
                VStack(spacing: 0) {
                    if viewModel.sections.count > 1 {
                        Picker("Library", selection: Binding(
                            get: { viewModel.selectedSection?.key ?? "" },
                            set: { newValue in
                                if let section = viewModel.sections.first(where: { $0.key == newValue }) {
                                    Task { await viewModel.selectSection(section) }
                                }
                            }
                        )) {
                            ForEach(viewModel.sections, id: \.key) { section in
                                Text(section.title).tag(section.key)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(palette.accentPrimary)
                        .padding(Layout.globalPadding)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading library...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(palette.stateError)
                            .padding(Layout.globalPadding)
                        Spacer()
                    } else {
                        GeometryReader { proxy in
                            let contentWidth = max(proxy.size.width - (Layout.globalPadding * 2), 0)
                            let columnWidth = max((contentWidth - Layout.columnSpacing) / 2, 0)
                            let rows = LibraryBrowseView.makeRows(from: viewModel.albums)

                            ScrollView {
                                LazyVStack(spacing: Layout.rowSpacing) {
                                    ForEach(rows) { row in
                                        AlbumRowView(
                                            row: row,
                                            palette: palette,
                                            width: columnWidth,
                                            playbackViewModel: playbackViewModel,
                                            signOut: signOut,
                                            ratingKeys: viewModel.ratingKeys(for:)
                                        )
                                    }
                                }
                                .padding(Layout.globalPadding)
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Library")
                        .font(LunaraTheme.Typography.displayBold(size: 20))
                        .foregroundStyle(palette.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        signOut()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let nowPlaying = playbackViewModel.nowPlaying {
                NowPlayingBarView(
                    state: nowPlaying,
                    palette: palette,
                    onTogglePlayPause: { playbackViewModel.togglePlayPause() }
                )
                    .padding(.horizontal, Layout.globalPadding)
                    .padding(.bottom, Layout.globalPadding)
            }
        }
        .overlay(alignment: .top) {
            if let message = playbackViewModel.errorMessage {
                PlaybackErrorBanner(message: message, palette: palette) {
                    playbackViewModel.clearError()
                }
                .padding(.horizontal, Layout.globalPadding)
            }
        }
        .task {
            await viewModel.loadSections()
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
        HStack(alignment: .top, spacing: LibraryBrowseView.Layout.columnSpacing) {
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
        AlbumCardContentView(album: album, palette: palette, width: width)
            .readHeight(onHeightChange)
            .frame(width: width, alignment: .top)
            .frame(height: height, alignment: .top)
            .background(palette.raised)
            .overlay(
                RoundedRectangle(cornerRadius: LibraryBrowseView.Layout.cardCornerRadius)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LibraryBrowseView.Layout.cardCornerRadius))
            .shadow(
                color: Color.black.opacity(LibraryBrowseView.Layout.cardShadowOpacity),
                radius: LibraryBrowseView.Layout.cardShadowRadius,
                x: 0,
                y: LibraryBrowseView.Layout.cardShadowYOffset
            )
    }
}

private struct AlbumCardContentView: View {
    let album: PlexAlbum
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumArtworkView(album: album, palette: palette)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: LibraryBrowseView.Layout.cardCornerRadius))
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
