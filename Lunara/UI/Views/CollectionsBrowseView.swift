import SwiftUI

struct CollectionsBrowseView: View {
    @StateObject var viewModel: CollectionsViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    let openSettings: () -> Void
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nowPlayingInsetHeight) private var nowPlayingInsetHeight
    @State private var errorToken = UUID()

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

        NavigationStack(path: $navigationPath) {
            ZStack {
                LinenBackgroundView(palette: palette)
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.collections.isEmpty {
                        ProgressView("Loading collections...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.collections.isEmpty, let error = viewModel.errorMessage {
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
                                LazyVGrid(columns: columns, alignment: .leading, spacing: Layout.rowSpacing) {
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
                                        .contextMenu {
                                            Button {
                                                playbackViewModel.downloadCollection(
                                                    collection: collection,
                                                    sectionKey: viewModel.sectionKey ?? ""
                                                )
                                            } label: {
                                                Label("Download Collection", systemImage: "arrow.down.circle")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, Layout.globalPadding)
                                .padding(.bottom, Layout.globalPadding)
                            }
                            .refreshable { await viewModel.refresh() }
                            .safeAreaInset(edge: .bottom) {
                                if nowPlayingInsetHeight > 0 {
                                    Color.clear.frame(height: nowPlayingInsetHeight)
                                }
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Collections")
                        .font(LunaraTheme.Typography.displayBold(size: 20))
                        .foregroundStyle(palette.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AlbumNavigationRequest.self) { request in
                AlbumDetailView(
                    album: request.album,
                    albumRatingKeys: request.albumRatingKeys,
                    playbackViewModel: playbackViewModel,
                    sessionInvalidationHandler: signOut
                )
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage, viewModel.collections.isEmpty == false {
                PlaybackErrorBanner(message: error, palette: palette) {
                    viewModel.clearError()
                }
                .padding(.horizontal, Layout.globalPadding)
                .padding(.top, 8)
                .transition(.opacity)
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
            await viewModel.loadCollectionsIfNeeded()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard newValue != nil else { return }
            let token = UUID()
            errorToken = token
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if errorToken == token {
                    viewModel.clearError()
                }
            }
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
                .lineLimit(nil)
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
    let size: ArtworkSize

    init(collection: PlexCollection, palette: LunaraTheme.PaletteColors? = nil, size: ArtworkSize = .grid) {
        self.collection = collection
        self.palette = palette
        self.size = size
    }

    var body: some View {
        let placeholder = palette?.raised ?? Color.gray.opacity(0.2)
        let secondaryText = palette?.textSecondary ?? Color.secondary

        if let request = artworkRequest() {
            ArtworkView(
                request: request,
                placeholder: placeholder,
                secondaryText: secondaryText
            )
        } else {
            placeholder
                .overlay(Text("No Art").font(.caption).foregroundStyle(secondaryText))
        }
    }

    private func artworkRequest() -> ArtworkRequest? {
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = ArtworkRequestBuilder(baseURL: baseURL, token: token)
        return builder.collectionRequest(for: collection, size: size)
    }
}
