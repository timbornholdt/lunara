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
        static let titleHeight: CGFloat = 40
        static let yearHeight: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let verticalSpacing: CGFloat = 16

        static func cardHeight(for width: CGFloat) -> CGFloat {
            width + titleHeight + yearHeight + verticalPadding + verticalSpacing
        }
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
                            let columns = [
                                GridItem(.fixed(columnWidth), spacing: Layout.columnSpacing),
                                GridItem(.fixed(columnWidth), spacing: Layout.columnSpacing)
                            ]

                            ScrollView {
                                LazyVGrid(columns: columns, spacing: Layout.rowSpacing) {
                                    ForEach(viewModel.albums, id: \.ratingKey) { album in
                                        NavigationLink {
                                            AlbumDetailView(
                                                album: album,
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
}

private struct AlbumCardView: View {
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
        .frame(width: width, height: LibraryBrowseView.Layout.cardHeight(for: width), alignment: .top)
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
