import SwiftUI

struct CollectionsBrowseView: View {
    @StateObject var viewModel: CollectionsViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) private var colorScheme
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
                            let rows = CollectionsBrowseView.makeRows(from: viewModel.collections)

                            ScrollView {
                                LazyVStack(spacing: Layout.rowSpacing) {
                                    ForEach(rows) { row in
                                        CollectionRowView(
                                            row: row,
                                            palette: palette,
                                            width: columnWidth,
                                            isPinned: viewModel.isPinned(_:)
                                        ) { collection in
                                            CollectionDetailView(
                                                collection: collection,
                                                sectionKey: viewModel.sectionKey ?? "",
                                                playbackViewModel: playbackViewModel,
                                                signOut: signOut
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, Layout.globalPadding)
                                .padding(.bottom, Layout.globalPadding)
                                .padding(.top, 8)
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
                    Button("Sign Out") {
                        signOut()
                    }
                }
            }
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

    private static func makeRows(from collections: [PlexCollection]) -> [CollectionRow] {
        var rows: [CollectionRow] = []
        rows.reserveCapacity((collections.count + 1) / 2)

        var index = 0
        while index < collections.count {
            let left = collections[index]
            let right = index + 1 < collections.count ? collections[index + 1] : nil
            rows.append(CollectionRow(id: index, left: left, right: right))
            index += 2
        }

        return rows
    }
}

private struct CollectionRow: Identifiable {
    let id: Int
    let left: PlexCollection
    let right: PlexCollection?
}

private struct CollectionRowView<Destination: View>: View {
    let row: CollectionRow
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat
    let isPinned: (PlexCollection) -> Bool
    let destination: (PlexCollection) -> Destination

    @State private var leftHeight: CGFloat = 0
    @State private var rightHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: CollectionsBrowseView.Layout.columnSpacing) {
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

    private func card(for collection: PlexCollection, height: CGFloat, measuredHeight: Binding<CGFloat>) -> some View {
        NavigationLink {
            destination(collection)
        } label: {
            CollectionCardView(
                collection: collection,
                palette: palette,
                width: width,
                height: height > 0 ? height : nil,
                onHeightChange: { measuredHeight.wrappedValue = $0 },
                isPinned: isPinned(collection)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CollectionCardView: View {
    let collection: PlexCollection
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat
    let height: CGFloat?
    let onHeightChange: (CGFloat) -> Void
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
        .readHeight(onHeightChange)
        .frame(width: width, alignment: .top)
        .frame(height: height, alignment: .top)
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
