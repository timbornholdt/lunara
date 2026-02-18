import SwiftUI
import UIKit

struct LibraryGridView: View {
    @State private var viewModel: LibraryGridViewModel
    @State private var selectedAlbum: Album?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)
    ]

    init(viewModel: LibraryGridViewModel) {
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
                        Text("Albums")
                            .lunaraHeading(.section, weight: .semibold)
                            .lineLimit(1)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search albums or artists"))
                .navigationDestination(item: $selectedAlbum) { album in
                    AlbumDetailView(viewModel: viewModel.makeAlbumDetailViewModel(for: album))
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
        if viewModel.albums.isEmpty,
           case .loading = viewModel.loadingState {
            VStack {
                Spacer()
                ProgressView("Loading albums...")
                Spacer()
            }
        } else if viewModel.albums.isEmpty,
                  case .error(let message) = viewModel.loadingState {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
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
                  viewModel.filteredAlbums.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.lunara(.textSecondary))
                Text("No albums matched your search.")
                    .font(albumSubtitleFont)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .multilineTextAlignment(.center)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.filteredAlbums) { album in
                        albumCard(for: album)
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded(currentAlbumID: album.plexID)
                                }
                            }
                    }
                }

                if viewModel.isLoadingNextPage {
                    ProgressView()
                        .padding(.top, 12)
                }
            }
        }
    }

    private func albumCard(for album: Album) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedAlbum = album
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    artworkView(for: album)

                    Text(album.title)
                        .font(albumTitleFont)
                        .lineLimit(2)
                        .foregroundStyle(Color.lunara(.textPrimary))

                    Text(album.subtitle)
                        .font(albumSubtitleFont)
                        .lineLimit(2)
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("Play") {
                Task {
                    await viewModel.playAlbum(album)
                }
            }
            .buttonStyle(LunaraPillButtonStyle())
        }
        .padding(12)
        .background(Color.lunara(.backgroundElevated), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func artworkView(for album: Album) -> some View {
        let thumbnailURL = viewModel.thumbnailURL(for: album.plexID)

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                Image(systemName: "opticaldisc")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            viewModel.loadThumbnailIfNeeded(for: album)
        }
    }

    private var albumTitleFont: Font {
        let size: CGFloat = 20
        if UIFont(name: "PlayfairDisplay-SemiBold", size: size) != nil {
            return .custom("PlayfairDisplay-SemiBold", size: size, relativeTo: .title3)
        }

        return .system(size: size, weight: .semibold, design: .serif)
    }

    private var albumSubtitleFont: Font {
        let size: CGFloat = 16
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .subheadline)
        }

        return .system(size: size, weight: .regular, design: .serif)
    }
}
