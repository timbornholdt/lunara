import SwiftUI
import UIKit

struct ArtistsListView: View {
    @State private var viewModel: ArtistsListViewModel
    @State private var selectedArtist: Artist?
    @Binding var externalSelectedArtist: Artist?

    init(viewModel: ArtistsListViewModel, externalSelectedArtist: Binding<Artist?> = .constant(nil)) {
        _viewModel = State(initialValue: viewModel)
        _externalSelectedArtist = externalSelectedArtist
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Artists")
                            .lunaraHeading(.section, weight: .semibold)
                            .lineLimit(1)
                    }
                }
                .toolbarBackground(Color.lunara(.backgroundBase), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search artists"))
                .navigationDestination(item: $selectedArtist) { artist in
                    ArtistDetailView(viewModel: viewModel.makeArtistDetailViewModel(for: artist))
                }
                .lunaraLinenBackground()
                .lunaraErrorBanner(using: viewModel.errorBannerState)
                .task {
                    await viewModel.loadInitialIfNeeded()
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .onChange(of: externalSelectedArtist) { _, newArtist in
                    if let newArtist {
                        selectedArtist = newArtist
                        externalSelectedArtist = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.artists.isEmpty,
           case .loading = viewModel.loadingState {
            VStack {
                Spacer()
                ProgressView("Loading artists...")
                Spacer()
            }
        } else if viewModel.artists.isEmpty,
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
        } else if viewModel.sectionedArtists.isEmpty,
                  !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.lunara(.textSecondary))
                Text("No artists matched your search.")
                    .font(subtitleFont)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .multilineTextAlignment(.center)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(viewModel.sectionedArtists, id: \.letter) { section in
                        sectionHeader(section.letter)
                        ForEach(section.artists) { artist in
                            artistRow(for: artist)
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

    private func artistRow(for artist: Artist) -> some View {
        Button {
            selectedArtist = artist
        } label: {
            HStack(spacing: 14) {
                artistThumbnail(for: artist)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(titleFont)
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let genre = artist.genre {
                            Text(genre)
                                .font(subtitleFont)
                                .foregroundStyle(Color.lunara(.textSecondary))
                                .lineLimit(1)
                        }
                        Text("\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums")")
                            .font(subtitleFont)
                            .foregroundStyle(Color.lunara(.textSecondary))
                            .lineLimit(1)
                    }
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
    private func artistThumbnail(for artist: Artist) -> some View {
        let thumbnailURL = viewModel.thumbnailURL(for: artist.plexID)

        ZStack {
            Circle()
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
                Image(systemName: "music.mic")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .clipShape(Circle())
        .task {
            viewModel.loadThumbnailIfNeeded(for: artist)
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
