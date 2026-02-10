import SwiftUI

struct CollectionDetailView: View {
    let collection: PlexCollection
    let sectionKey: String
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme

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
                    AlbumGridView(
                        albums: viewModel.albums,
                        palette: palette,
                        playbackViewModel: playbackViewModel,
                        signOut: signOut,
                        ratingKeys: viewModel.ratingKeys(for:)
                    )
                }
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let nowPlaying = playbackViewModel.nowPlaying {
                NowPlayingBarView(
                    state: nowPlaying,
                    palette: palette,
                    onTogglePlayPause: { playbackViewModel.togglePlayPause() }
                )
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                .padding(.bottom, LunaraTheme.Layout.globalPadding)
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
