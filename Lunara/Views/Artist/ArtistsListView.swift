import SwiftUI
import UIKit

struct ArtistsListView: View {
    @State private var viewModel: ArtistsListViewModel
    @State private var selectedArtist: Artist?
    /// Shared background-refresh status; nil in previews/tests that don't exercise it.
    private let refreshStatus: RefreshStatusService?
    /// Release radar (Lunara-nlo); nil hides the card.
    private let radarService: RadarService?

    init(
        viewModel: ArtistsListViewModel,
        refreshStatus: RefreshStatusService? = nil,
        radarService: RadarService? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.refreshStatus = refreshStatus
        self.radarService = radarService
    }

    var body: some View {
        NavigationStack {
            content
                // Loading/error/no-results branches hug their text otherwise,
                // shrinking the linen background to a column (Lunara-2sp).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .task(id: refreshStatus?.successToken ?? 0) {
                    await viewModel.applyBackgroundRefreshUpdateIfNeeded(successToken: refreshStatus?.successToken ?? 0)
                }
                .task(id: refreshStatus?.failureToken ?? 0) {
                    viewModel.applyBackgroundRefreshFailureIfNeeded(
                        failureToken: refreshStatus?.failureToken ?? 0,
                        message: refreshStatus?.lastErrorMessage
                    )
                }
                .refreshable {
                    await viewModel.refresh()
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
                    radarCard
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

    /// Entry point to the release radar, pinned above the artist list when the
    /// search is idle (Lunara-nlo).
    @ViewBuilder
    private var radarCard: some View {
        if let radarService,
           viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NavigationLink {
                RadarView(service: radarService)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.lunara(.textPrimary))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Release Radar")
                            .font(titleFont)
                            .foregroundStyle(Color.lunara(.textPrimary))
                        Text(radarSubtitle)
                            .font(subtitleFont)
                            .foregroundStyle(Color.lunara(.textSecondary))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.lunara(.backgroundElevated))
                }
            }
            .buttonStyle(.plain)
            .task {
                await radarService.loadCached()
            }
        }
    }

    private var radarSubtitle: String {
        let count = radarService?.entries.count ?? 0
        switch count {
        case 0: return "Upcoming albums from artists you love"
        case 1: return "1 upcoming album"
        default: return "\(count) upcoming albums"
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
