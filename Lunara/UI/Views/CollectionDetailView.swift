import SwiftUI

struct CollectionDetailView: View {
    let collection: PlexCollection
    let sectionKey: String
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nowPlayingInsetHeight) private var nowPlayingInsetHeight

    @StateObject private var viewModel: CollectionAlbumsViewModel

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
            sessionInvalidationHandler: signOut
        ))
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

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
                                }
                            }
                            .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                            .padding(.bottom, LunaraTheme.Layout.globalPadding)
                        }
                        .safeAreaInset(edge: .bottom) {
                            if nowPlayingInsetHeight > 0 {
                                Color.clear.frame(height: nowPlayingInsetHeight)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(collection.title)
                    .font(LunaraTheme.Typography.displayBold(size: 20))
                    .foregroundStyle(palette.textPrimary)
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
