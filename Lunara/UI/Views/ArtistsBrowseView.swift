import SwiftUI

struct ArtistsBrowseView: View {
    @StateObject var viewModel: ArtistsViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    let openSettings: () -> Void
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nowPlayingInsetHeight) private var nowPlayingInsetHeight
    @State private var searchQuery = ""
    @State private var errorToken = UUID()
    @State private var artistScrollTarget: String?

    enum Layout {
        static let globalPadding = LunaraTheme.Layout.globalPadding
        static let rowSpacing: CGFloat = 12
        static let rowCornerRadius = LunaraTheme.Layout.cardCornerRadius
        static let indexInset: CGFloat = 36
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)
        let filteredArtists = viewModel.filteredArtists(query: searchQuery)
        let sections = AlphabetSectionBuilder.sections(from: filteredArtists) { artist in
            let sort = artist.titleSort?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let sort, !sort.isEmpty {
                return sort
            }
            return artist.title
        }

        NavigationStack(path: $navigationPath) {
            ZStack {
                LinenBackgroundView(palette: palette)
                VStack(spacing: 0) {
                    searchField(palette: palette)
                        .padding(.horizontal, Layout.globalPadding)

                    if viewModel.isLoading && viewModel.artists.isEmpty {
                        ProgressView("Loading artists...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.artists.isEmpty, let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(palette.stateError)
                            .padding(Layout.globalPadding)
                        Spacer()
                    } else {
                        ZStack(alignment: .topTrailing) {
                            ScrollViewReader { scrollProxy in
                                ScrollView {
                                    LazyVStack(spacing: Layout.rowSpacing) {
                                        ForEach(sections) { section in
                                            Color.clear
                                                .frame(height: 0.5)
                                                .id(section.id)

                                            ForEach(section.items, id: \.ratingKey) { artist in
                                                NavigationLink {
                                                    ArtistDetailView(
                                                        artistRatingKey: artist.ratingKey,
                                                        playbackViewModel: playbackViewModel,
                                                        sessionInvalidationHandler: signOut
                                                    )
                                                } label: {
                                                    ArtistRowView(artist: artist, palette: palette)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, Layout.globalPadding)
                                    .padding(.trailing, Layout.indexInset)
                                    .padding(.bottom, Layout.globalPadding)
                                }
                                .safeAreaInset(edge: .bottom) {
                                    if nowPlayingInsetHeight > 0 {
                                        Color.clear.frame(height: nowPlayingInsetHeight)
                                    }
                                }
                                .onChange(of: artistScrollTarget) { _, newValue in
                                    guard let newValue else { return }
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        scrollProxy.scrollTo(newValue, anchor: .top)
                                    }
                                }
                            }

                            if sections.count > 1 {
                                AlphabetIndexOverlay(letters: sections.map(\.id), palette: palette) { letter in
                                    artistScrollTarget = letter
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
                    Text("Artists")
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
            if let error = viewModel.errorMessage, viewModel.artists.isEmpty == false {
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
            await viewModel.loadArtistsIfNeeded()
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

    private func searchField(palette: LunaraTheme.PaletteColors) -> some View {
        TextField("Search artists", text: $searchQuery)
            .font(LunaraTheme.Typography.displayRegular(size: 15))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(palette.raised)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.rowCornerRadius)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Layout.rowCornerRadius))
    }
}

private struct ArtistRowView: View {
    let artist: PlexArtist
    let palette: LunaraTheme.PaletteColors

    var body: some View {
        HStack {
            Text(artist.title)
                .font(LunaraTheme.Typography.displayBold(size: 16))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
    }
}
