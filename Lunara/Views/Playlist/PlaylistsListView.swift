import SwiftUI
import UIKit

struct PlaylistsListView: View {
    @State private var viewModel: PlaylistsListViewModel
    @State private var selectedPlaylist: Playlist?

    init(viewModel: PlaylistsListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Playlists")
                            .lunaraHeading(.section, weight: .semibold)
                            .lineLimit(1)
                    }
                }
                .toolbarBackground(Color.lunara(.backgroundBase), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search playlists"))
                .navigationDestination(item: $selectedPlaylist) { playlist in
                    PlaylistDetailView(viewModel: viewModel.makePlaylistDetailViewModel(for: playlist))
                }
                .lunaraLinenBackground()
                .lunaraErrorBanner(using: viewModel.errorBannerState)
                .task {
                    await viewModel.loadInitialIfNeeded()
                }
                .refreshable {
                    await viewModel.refresh()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.playlists.isEmpty,
           case .loading = viewModel.loadingState {
            VStack {
                Spacer()
                ProgressView("Loading playlists...")
                Spacer()
            }
        } else if viewModel.playlists.isEmpty,
                  case .error(let message) = viewModel.loadingState {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.lunara(.accentPrimary))
                Text(message)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(LunaraPillButtonStyle())
                Spacer()
            }
        } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  viewModel.pinnedPlaylists.isEmpty,
                  viewModel.unpinnedPlaylists.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.lunara(.textSecondary))
                Text("No playlists matched your search.")
                    .font(subtitleFont)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .multilineTextAlignment(.center)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !viewModel.pinnedPlaylists.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(viewModel.pinnedPlaylists) { playlist in
                            playlistRow(for: playlist)
                        }
                    }

                    if !viewModel.unpinnedPlaylists.isEmpty {
                        if !viewModel.pinnedPlaylists.isEmpty {
                            sectionHeader("All Playlists")
                        }
                        ForEach(viewModel.unpinnedPlaylists) { playlist in
                            playlistRow(for: playlist)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(sectionHeadingFont)
            .foregroundStyle(Color.lunara(.textPrimary))
            .padding(.top, 4)
    }

    private func playlistRow(for playlist: Playlist) -> some View {
        Button {
            selectedPlaylist = playlist
        } label: {
            HStack(spacing: 14) {
                playlistThumbnail(for: playlist)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title)
                        .font(titleFont)
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .lineLimit(2)

                    Text(playlist.subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
            .padding(12)
            .background(Color.lunara(.backgroundElevated), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func playlistThumbnail(for playlist: Playlist) -> some View {
        let thumbnailURL = viewModel.thumbnailURL(for: playlist.plexID)

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.lunara(.backgroundBase))

            if let thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            viewModel.loadThumbnailIfNeeded(for: playlist)
        }
    }

    private var titleFont: Font {
        let size: CGFloat = 18
        if UIFont(name: "PlayfairDisplay-SemiBold", size: size) != nil {
            return .custom("PlayfairDisplay-SemiBold", size: size, relativeTo: .headline)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    private var subtitleFont: Font {
        let size: CGFloat = 15
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .subheadline)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    private var sectionHeadingFont: Font {
        let token = LunaraVisualTokens.headingToken(for: .section, weight: .semibold)
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(token.preferredFontName, size: token.size, relativeTo: token.relativeTextStyle)
        }
        return .system(size: token.size, weight: token.fallbackWeight, design: .serif)
    }
}
