import SwiftUI

struct LibraryBrowseView: View {
    @StateObject var viewModel: LibraryViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorToken = UUID()

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        NavigationStack {
            ZStack {
                LinenBackgroundView(palette: palette)
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.albums.isEmpty {
                        ProgressView("Loading library...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.albums.isEmpty, let error = viewModel.errorMessage {
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(palette.textPrimary)
                    }
                }
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
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage, viewModel.albums.isEmpty == false {
                PlaybackErrorBanner(message: error, palette: palette) {
                    viewModel.clearError()
                }
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
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
            await viewModel.loadSectionsIfNeeded()
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
