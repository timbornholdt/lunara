import SwiftUI

struct LibraryBrowseView: View {
    @StateObject var viewModel: LibraryViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorToken = UUID()
    @State private var albumScrollTarget: String?

    private enum Layout {
        static let indexInset: CGFloat = 36
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)
        let albumIndexLetters = AlbumGridView.sectionLetters(from: viewModel.albums)

        NavigationStack(path: $navigationPath) {
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
                        ZStack(alignment: .topTrailing) {
                            AlbumGridView(
                                albums: viewModel.albums,
                                palette: palette,
                                playbackViewModel: playbackViewModel,
                                signOut: signOut,
                                ratingKeys: viewModel.ratingKeys(for:),
                                scrollTarget: albumScrollTarget,
                                trailingContentInset: Layout.indexInset
                            )

                            if albumIndexLetters.count > 1 {
                                AlphabetIndexOverlay(letters: albumIndexLetters, palette: palette) { letter in
                                    albumScrollTarget = letter
                                }
                                .padding(.trailing, 6)
                                .padding(.top, 6)
                                .padding(.bottom, 80)
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
                    Text("Albums")
                        .font(LunaraTheme.Typography.displayBold(size: 20))
                        .foregroundStyle(palette.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        signOut()
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
            if let error = viewModel.errorMessage, viewModel.albums.isEmpty == false {
                PlaybackErrorBanner(message: error, palette: palette) {
                    viewModel.clearError()
                }
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                .padding(.top, 8)
                .transition(.opacity)
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
