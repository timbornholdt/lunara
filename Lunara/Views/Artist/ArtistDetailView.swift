import SwiftUI
import UIKit

struct ArtistDetailView: View {
    @State private var viewModel: ArtistDetailViewModel
    @Environment(\.showNowPlaying) private var showNowPlaying
    @Environment(\.lastFMClient) private var lastFMClient
    @Environment(\.musicBrainzClient) private var musicBrainzClient
    @Environment(\.ticketmasterClient) private var ticketmasterClient
    @State private var selectedAlbum: Album?
    @State private var isBioExpanded = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)
    ]

    init(viewModel: ArtistDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                concertsSection
                albumsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .lunaraLinenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.artist.name)
                    .lunaraHeading(.section, weight: .semibold)
                    .lineLimit(1)
            }
        }
        .toolbarBackground(Color.lunara(.backgroundBase), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedAlbum) { album in
            AlbumDetailView(viewModel: viewModel.makeAlbumDetailViewModel(for: album))
        }
        .lunaraErrorBanner(using: viewModel.errorBannerState)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.loadLastFMBioIfNeeded(using: lastFMClient)
            await viewModel.loadConcertsIfNeeded(using: ticketmasterClient)
            await viewModel.loadEnrichmentIfNeeded(using: musicBrainzClient)
        }
    }

    // MARK: - Header

    /// Editorial byline header (Lunara-2z2): compact portrait beside the name,
    /// genre, and icon actions — the page leads with reading, not a hero image.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                headerArtwork
                    .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.artist.name)
                        .font(titleHeadingFont())
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    if let genre = viewModel.artist.genre {
                        Text(genre)
                            .font(subtitleFont())
                            .foregroundStyle(Color.lunara(.textSecondary))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.lunara(.backgroundBase), in: Capsule())
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await viewModel.playAll()
                                showNowPlaying.wrappedValue = true
                            }
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(LunaraCircleButtonStyle())
                        .accessibilityLabel("Play All")

                        Button {
                            Task {
                                await viewModel.shuffle()
                                showNowPlaying.wrappedValue = true
                            }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(LunaraCircleButtonStyle(role: .secondary))
                        .accessibilityLabel("Shuffle")
                    }
                }

                Spacer(minLength: 0)
            }

            bioSection

            externalLinksRow
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lunara(.backgroundElevated))
        }
    }

    /// Long-form bio set for READING (Lunara-2z2): primary-color serif with
    /// generous line spacing, real paragraphs when expanded, collapsed to a
    /// teaser by default.
    @ViewBuilder
    private var bioSection: some View {
        if let bio = viewModel.displayBio {
            VStack(alignment: .leading, spacing: 10) {
                if isBioExpanded {
                    ForEach(Array(Self.bioParagraphs(of: bio).enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(bioFont())
                            .lineSpacing(6)
                            .foregroundStyle(Color.lunara(.textPrimary))
                    }
                } else {
                    Text(bio)
                        .font(bioFont())
                        .lineSpacing(6)
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .lineLimit(5)
                }

                Button(isBioExpanded ? "Show less" : "Read more") {
                    withAnimation {
                        isBioExpanded.toggle()
                    }
                }
                .font(subtitleFont())
                .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
    }

    /// Splits a bio into displayable paragraphs: newline-separated, blanks dropped.
    static func bioParagraphs(of text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func bioFont() -> Font {
        let size: CGFloat = 15
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .body)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    /// Outbound links from MusicBrainz enrichment (Lunara-uww.6.2).
    @ViewBuilder
    private var externalLinksRow: some View {
        if let links = viewModel.externalLinks {
            HStack(spacing: 16) {
                if let wikipediaURL = links.wikipediaURL {
                    Link("Wikipedia", destination: wikipediaURL)
                }
                Link("MusicBrainz", destination: links.musicBrainzURL)
                if let homepageURL = links.homepageURL {
                    Link("Website", destination: homepageURL)
                }
            }
            .font(subtitleFont())
            .foregroundStyle(Color.lunara(.textPrimary))
        }
    }

    @ViewBuilder
    private var headerArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.lunara(.backgroundBase))

            if let artworkURL = viewModel.artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "music.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsSection: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            VStack {
                Spacer()
                ProgressView("Loading albums...")
                Spacer()
            }
        case .error(let message):
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .multilineTextAlignment(.center)
                Spacer()
            }
        case .loaded:
            if viewModel.albums.isEmpty {
                Text("No albums for this artist.")
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textSecondary))
            } else {
                // Header matches the page's other sections; pairs with
                // "Not in your library" below (Lunara-2ay).
                Text("In your library")
                    .lunaraHeading(.section, weight: .semibold)
                    .padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.albums) { album in
                        albumCard(for: album)
                    }
                }
                missingAlbumsSection
            }
        }
    }

    /// Upcoming shows near home for this artist (Lunara-uww.6.4). Hidden when
    /// none, when the artist doesn't tour, or when no API key is configured.
    @ViewBuilder
    private var concertsSection: some View {
        if !viewModel.upcomingConcerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Upcoming shows")
                    .lunaraHeading(.section, weight: .semibold)
                    .padding(.top, 12)

                ForEach(viewModel.upcomingConcerts) { event in
                    concertRow(event)
                }
            }
        }
    }

    @ViewBuilder
    private func concertRow(_ event: ConcertEvent) -> some View {
        let label = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text([event.venueName, event.cityName].compactMap { $0 }.joined(separator: " · "))
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textPrimary))
                    .lineLimit(1)
                Text(event.localDate)
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
            Spacer()
            if event.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .padding(.vertical, 6)

        if let url = event.url {
            Link(destination: url) { label }
        } else {
            label
        }
    }

    /// Studio albums MusicBrainz knows that aren't in the Plex library —
    /// the rediscovery hook for releases you don't own yet (Lunara-uww.6.3).
    @ViewBuilder
    private var missingAlbumsSection: some View {
        if !viewModel.missingAlbums.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not in your library")
                    .lunaraHeading(.section, weight: .semibold)
                    .padding(.top, 12)

                ForEach(viewModel.missingAlbums) { releaseGroup in
                    Link(destination: releaseGroup.musicBrainzURL) {
                        HStack {
                            Text(releaseGroup.title)
                                .font(subtitleFont())
                                .foregroundStyle(Color.lunara(.textPrimary))
                                .lineLimit(1)
                            Spacer()
                            if let year = releaseGroup.firstReleaseYear {
                                Text(String(year))
                                    .font(subtitleFont())
                                    .foregroundStyle(Color.lunara(.textSecondary))
                            }
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.lunara(.textSecondary))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func albumCard(for album: Album) -> some View {
        Button {
            selectedAlbum = album
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                albumArtworkView(for: album)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(albumTitleFont)
                        .lineLimit(2)
                        .foregroundStyle(Color.lunara(.textPrimary))

                    if let year = album.year {
                        Text(String(year))
                            .font(albumSubtitleFont)
                            .lineLimit(1)
                            .foregroundStyle(Color.lunara(.textSecondary))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .background(Color.lunara(.backgroundElevated))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") {
                Task { await viewModel.queueAlbumNext(album) }
            }
            Button("Play Later", systemImage: "text.append") {
                Task { await viewModel.queueAlbumLater(album) }
            }
        }
    }

    @ViewBuilder
    private func albumArtworkView(for album: Album) -> some View {
        let thumbnailURL = viewModel.albumThumbnailURL(for: album.plexID)

        SquareArtworkView {
            if let thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .task {
            viewModel.loadAlbumThumbnailIfNeeded(for: album)
        }
    }

    // MARK: - Fonts

    private func titleHeadingFont() -> Font {
        let token = LunaraVisualTokens.headingToken(for: .title, weight: .semibold)
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(token.preferredFontName, size: token.size, relativeTo: token.relativeTextStyle)
        }
        return .system(size: token.size, weight: token.fallbackWeight, design: .serif)
    }

    private func subtitleFont() -> Font {
        let size: CGFloat = 16
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .subheadline)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    private var albumTitleFont: Font {
        let size: CGFloat = 15
        if UIFont(name: "PlayfairDisplay-SemiBold", size: size) != nil {
            return .custom("PlayfairDisplay-SemiBold", size: size, relativeTo: .subheadline)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    private var albumSubtitleFont: Font {
        let size: CGFloat = 13
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .caption)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }
}
