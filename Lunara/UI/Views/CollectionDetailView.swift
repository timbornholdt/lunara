import SwiftUI

struct CollectionDetailView: View {
    let collection: PlexCollection
    let sectionKey: String
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nowPlayingInsetHeight) private var nowPlayingInsetHeight

    @StateObject private var viewModel: CollectionAlbumsViewModel
    @State private var scrollOffset: CGFloat = 0

    init(
        collection: PlexCollection,
        sectionKey: String,
        playbackViewModel: PlaybackViewModel,
        signOut: @escaping () -> Void
    ) {
        self.collection = collection
        self.sectionKey = sectionKey
        self.playbackViewModel = playbackViewModel
        self.signOut = signOut
        _viewModel = StateObject(wrappedValue: CollectionAlbumsViewModel(
            collection: collection,
            sectionKey: sectionKey,
            sessionInvalidationHandler: signOut,
            playbackController: playbackViewModel
        ))
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)
        let navTitleOpacity = CollectionHeaderMetrics.navTitleOpacity(for: scrollOffset)

        ZStack {
            LinenBackgroundView(palette: palette)
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Loading collection...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(palette.stateError)
                        .padding(LunaraTheme.Layout.globalPadding)
                    Spacer()
                } else {
                    GeometryReader { proxy in
                        let contentWidth = max(proxy.size.width - (LunaraTheme.Layout.globalPadding * 2), 0)
                        let columnWidth = max((contentWidth - 16) / 2, 0)
                        let columns = [
                            GridItem(.fixed(columnWidth), spacing: 16),
                            GridItem(.fixed(columnWidth), spacing: 16)
                        ]

                        ScrollView {
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: CollectionScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("collectionScroll")).minY
                                    )
                            }
                            .frame(height: 0)

                            VStack(spacing: 0) {
                                collectionHeader(palette: palette)

                                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                                    ForEach(viewModel.albums, id: \.ratingKey) { album in
                                        NavigationLink {
                                            AlbumDetailView(
                                                album: album,
                                                albumRatingKeys: viewModel.ratingKeys(for: album),
                                                playbackViewModel: playbackViewModel,
                                                sessionInvalidationHandler: signOut
                                            )
                                        } label: {
                                            CollectionAlbumCardView(album: album, palette: palette, width: columnWidth)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                playbackViewModel.downloadAlbum(
                                                    album: album,
                                                    albumRatingKeys: viewModel.ratingKeys(for: album)
                                                )
                                            } label: {
                                                Label("Download Album", systemImage: "arrow.down.circle")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                                .padding(.top, 14)
                                .padding(.bottom, LunaraTheme.Layout.globalPadding)
                            }
                        }
                        .safeAreaInset(edge: .bottom) {
                            if nowPlayingInsetHeight > 0 {
                                Color.clear.frame(height: nowPlayingInsetHeight)
                            }
                        }
                        .coordinateSpace(name: "collectionScroll")
                        .onPreferenceChange(CollectionScrollOffsetPreferenceKey.self) { value in
                            scrollOffset = value
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(collection.title)
                    .font(LunaraTheme.Typography.displayBold(size: 17))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .opacity(navTitleOpacity)
                    .animation(.easeInOut(duration: 0.2), value: navTitleOpacity)
            }
        }
        .overlay(alignment: .top) {
            if let message = playbackViewModel.errorMessage {
                PlaybackErrorBanner(message: message, palette: palette) {
                    playbackViewModel.clearError()
                }
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
            }
        }
        .task {
            await viewModel.loadAlbums()
        }
    }

    private func collectionHeader(palette: LunaraTheme.PaletteColors) -> some View {
        let headerHeight = CollectionHeaderMetrics.headerHeight(for: scrollOffset)
        return ZStack(alignment: .bottomLeading) {
            CollectionHeroMarqueeView(
                albums: viewModel.marqueeAlbums,
                palette: palette,
                height: headerHeight
            )

            LinearGradient(
                colors: [Color.black.opacity(0.03), Color.black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(collection.title)
                    .font(LunaraTheme.Typography.displayBold(size: 30))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.playCollection(shuffled: false) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(CollectionHeaderActionButtonStyle())

                    Button {
                        Task { await viewModel.playCollection(shuffled: true) }
                    } label: {
                        Label("Shuffle All", systemImage: "shuffle")
                    }
                    .buttonStyle(CollectionHeaderActionButtonStyle())
                }
                .disabled(viewModel.albums.isEmpty || viewModel.isPreparingPlayback)
                .opacity(viewModel.albums.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, LunaraTheme.Layout.globalPadding)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight)
        .clipped()
    }
}

struct CollectionHeaderMetrics {
    static let maxHeaderHeight: CGFloat = 300
    static let minHeaderHeight: CGFloat = 132

    static func headerHeight(for offset: CGFloat) -> CGFloat {
        let rawHeight = maxHeaderHeight + min(0, offset)
        return min(maxHeaderHeight, max(minHeaderHeight, rawHeight))
    }

    static func navTitleOpacity(for offset: CGFloat) -> Double {
        let fadeStart: CGFloat = -60
        let fadeEnd: CGFloat = -140
        let progress = min(1, max(0, (offset - fadeStart) / (fadeEnd - fadeStart)))
        return Double(progress)
    }
}

struct CollectionHeroMarqueeMotion {
    let baseWidth: CGFloat
    let speed: CGFloat

    func offset(at date: Date, startDate: Date) -> CGFloat {
        guard baseWidth > 0, speed > 0 else { return 0 }
        let elapsed = max(date.timeIntervalSince(startDate), 0)
        let distance = CGFloat(elapsed) * speed
        let wrapped = distance.truncatingRemainder(dividingBy: baseWidth)
        return wrapped
    }
}

private struct CollectionHeroMarqueeView: View {
    let albums: [PlexAlbum]
    let palette: LunaraTheme.PaletteColors
    let height: CGFloat

    @State private var startDate = Date()

    private enum Layout {
        static let tileSize: CGFloat = 92
        static let spacing: CGFloat = 10
        static let speed: CGFloat = 20
        static let rowOffset: CGFloat = 18
    }

    var body: some View {
        let duplicated = albums + albums
        let baseWidth = baseStripWidth(count: albums.count)
        let motion = CollectionHeroMarqueeMotion(baseWidth: baseWidth, speed: Layout.speed)

        ZStack {
            if albums.isEmpty {
                LinenBackgroundView(palette: palette)
                    .overlay(Color.black.opacity(0.08))
            } else {
                TimelineView(.animation) { context in
                    let wrappedOffset = motion.offset(at: context.date, startDate: startDate)

                    VStack(spacing: Layout.spacing) {
                        marqueeRow(albums: duplicated, offset: -baseWidth + wrappedOffset)
                        marqueeRow(albums: Array(duplicated.reversed()), offset: -baseWidth + wrappedOffset + Layout.rowOffset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
                }
            }
        }
        .frame(height: height)
        .onAppear {
            startDate = Date()
        }
    }

    private func marqueeRow(albums: [PlexAlbum], offset: CGFloat) -> some View {
        HStack(spacing: Layout.spacing) {
            ForEach(Array(albums.enumerated()), id: \.offset) { _, album in
                AlbumArtworkView(album: album, palette: palette, size: .grid)
                    .frame(width: Layout.tileSize, height: Layout.tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .offset(x: offset)
        .clipped()
    }

    private func baseStripWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * (Layout.tileSize + Layout.spacing)
    }
}

private struct CollectionHeaderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(configuration.isPressed ? 0.26 : 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CollectionAlbumCardView: View {
    let album: PlexAlbum
    let palette: LunaraTheme.PaletteColors
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumArtworkView(album: album, palette: palette)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
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
        .frame(width: width, alignment: .top)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 8,
            x: 0,
            y: 1
        )
    }

    private var metadataText: String {
        let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = album.year.map(String.init)
        switch (artist?.isEmpty == false ? artist : nil, year) {
        case let (.some(name), .some(yearValue)):
            return "\(name) - \(yearValue)"
        case let (.some(name), .none):
            return name
        case let (.none, .some(yearValue)):
            return yearValue
        default:
            return " "
        }
    }
}

private struct CollectionScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
