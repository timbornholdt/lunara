import SwiftUI

struct CollectionsBrowseView: View {
    @StateObject var viewModel: CollectionsViewModel
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
                    if viewModel.isLoading {
                        ProgressView("Loading collections...")
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
                                    ForEach(viewModel.collections, id: \.ratingKey) { collection in
                                        NavigationLink {
                                            CollectionDetailView(
                                                collection: collection,
                                                sectionKey: viewModel.sectionKey ?? "",
                                                playbackViewModel: playbackViewModel,
                                                signOut: signOut
                                            )
                                        } label: {
                                            CollectionCardView(
                                                collection: collection,
                                                palette: palette,
                                                width: columnWidth,
                                                isPinned: viewModel.isPinned(collection)
                                            )
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
                    Text("Collections")
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
            await viewModel.loadCollections()
        }
    }
}

private struct CollectionCardView: View {
    let collection: PlexCollection
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat
    let isPinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CollectionArtworkView(collection: collection, palette: palette)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: CollectionsBrowseView.Layout.cardCornerRadius))
                .clipped()

            Text(collection.title)
                .font(LunaraTheme.Typography.displayBold(size: 15))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(width: width, alignment: .top)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: CollectionsBrowseView.Layout.cardCornerRadius)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CollectionsBrowseView.Layout.cardCornerRadius))
        .shadow(
            color: Color.black.opacity(CollectionsBrowseView.Layout.cardShadowOpacity),
            radius: CollectionsBrowseView.Layout.cardShadowRadius,
            x: 0,
            y: CollectionsBrowseView.Layout.cardShadowYOffset
        )
    }

    private var backgroundColor: Color {
        if isPinned {
            return palette.accentSecondary.opacity(0.12)
        }
        return palette.raised
    }

    private var borderColor: Color {
        if isPinned {
            return palette.accentSecondary.opacity(0.45)
        }
        return palette.borderSubtle
    }
}

private struct CollectionArtworkView: View {
    let collection: PlexCollection
    let palette: LunaraTheme.PaletteColors?

    init(collection: PlexCollection, palette: LunaraTheme.PaletteColors? = nil) {
        self.collection = collection
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
        let resolver = CollectionArtworkResolver(artworkBuilder: builder)
        return resolver.artworkURL(for: collection)
    }
}
