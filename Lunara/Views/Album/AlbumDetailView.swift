import SwiftUI
import UIKit

struct TagFilterNavigation: Identifiable, Hashable {
    let id = UUID()
    let genres: Set<String>
    let styles: Set<String>
    let moods: Set<String>
}

struct AlbumDetailView: View {
    @State private var viewModel: AlbumDetailViewModel
    @Environment(\.showNowPlaying) private var showNowPlaying
    @State private var selectedArtist: Artist?
    @State private var tagFilterNavigation: TagFilterNavigation?

    init(viewModel: AlbumDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            viewModel.palette.background
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AlbumDetailLayout.sectionSpacing) {
                    headerCard
                    trackList
                    metadataSections
                    downloadButton
                }
                .padding(.horizontal, AlbumDetailLayout.horizontalPadding)
                .padding(.top, AlbumDetailLayout.topContentPadding)
                .padding(.bottom, 80)
                .containerRelativeFrame(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .lunaraLinenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.album.title)
                    .font(sectionHeadingFont())
                    .foregroundStyle(viewModel.palette.textPrimary)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.4), value: viewModel.palette)
            }
        }
        .lunaraErrorBanner(using: viewModel.errorBannerState)
        .navigationDestination(item: $selectedArtist) { artist in
            ArtistDetailView(viewModel: viewModel.makeArtistDetailViewModel(for: artist))
        }
        .navigationDestination(item: $tagFilterNavigation) { nav in
            TagFilterView(viewModel: viewModel.makeTagFilterViewModel(
                initialGenres: nav.genres,
                initialStyles: nav.styles,
                initialMoods: nav.moods
            ))
        }
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshDownloadState()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            Text(viewModel.album.title)
                .font(titleHeadingFont())
                .foregroundStyle(viewModel.palette.textPrimary)
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            Button {
                Task {
                    if let artist = await viewModel.findArtist() {
                        selectedArtist = artist
                    }
                }
            } label: {
                Text(viewModel.album.artistName)
                    .font(AlbumDetailTypography.font(for: .subtitleMetadata))
                    .foregroundStyle(viewModel.palette.textSecondary)
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            Text(metadataText)
                .font(AlbumDetailTypography.font(for: .subtitleMetadata))
                .foregroundStyle(viewModel.palette.textSecondary)
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            Button("Play Album") {
                Task {
                    await viewModel.playAlbum()
                    showNowPlaying.wrappedValue = true
                }
            }
            .buttonStyle(LunaraPillButtonStyle())
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.palette.background.opacity(0.6))
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)
        }
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") {
                Task { await viewModel.queueAlbumNext() }
            }
            Button("Play Later", systemImage: "text.append") {
                Task { await viewModel.queueAlbumLater() }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(viewModel.palette.background)

            if let artworkURL = viewModel.artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 48))
                    .foregroundStyle(viewModel.palette.textSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Download Button

    @ViewBuilder
    private var downloadButton: some View {
        switch viewModel.albumDownloadState {
        case .idle:
            Button {
                Task { await viewModel.downloadAlbum() }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Download for Offline")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(viewModel.palette.textSecondary)
            }

        case .downloading(let completed, let total):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(viewModel.palette.textSecondary)
                Text("Downloading...")
                    .font(.subheadline)
                    .foregroundStyle(viewModel.palette.textSecondary)
                Spacer()
                Text("\(completed)/\(total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(viewModel.palette.textSecondary)
            }

        case .complete:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Downloaded")
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(viewModel.palette.textSecondary)
            .contextMenu {
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    Task { await viewModel.removeDownload() }
                }
            }

        case .failed(let message):
            HStack {
                Image(systemName: "exclamationmark.circle")
                Text(message)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Track List

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tracks")
                .font(sectionHeadingFont())
                .foregroundStyle(viewModel.palette.textPrimary)
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            switch viewModel.loadingState {
            case .idle, .loading:
                ProgressView("Loading tracks...")
                    .padding(.vertical, 12)
            case .error(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.palette.textSecondary)
            case .loaded:
                if viewModel.tracks.isEmpty {
                    Text("No tracks available for this album.")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.palette.textSecondary)
                } else {
                    ForEach(viewModel.tracks) { track in
                        trackRow(track)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.palette.background.opacity(0.6))
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)
        }
    }

    private func trackRow(_ track: Track) -> some View {
        let secondaryArtist = AlbumTrackPresentation.secondaryArtist(
            trackArtist: track.artistName,
            albumArtist: viewModel.album.artistName
        )

        return Button {
            Task {
                await viewModel.playTrackNow(track)
                showNowPlaying.wrappedValue = true
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(track.trackNumber)")
                    .font(AlbumDetailTypography.font(for: .trackNumber))
                    .foregroundStyle(viewModel.palette.textSecondary)
                    .frame(width: 24, alignment: .trailing)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(AlbumDetailTypography.font(for: .trackTitle))
                        .foregroundStyle(viewModel.palette.textPrimary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let secondaryArtist {
                        Text(secondaryArtist)
                            .font(AlbumDetailTypography.font(for: .trackSecondaryArtist))
                            .foregroundStyle(viewModel.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)

                Spacer()

                Text(track.formattedDuration)
                    .font(AlbumDetailTypography.font(for: .trackDuration))
                    .foregroundStyle(viewModel.palette.textSecondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Now", systemImage: "play.fill") {
                Task {
                    await viewModel.playTrackNow(track)
                    showNowPlaying.wrappedValue = true
                }
            }
            Button("Play Next", systemImage: "text.insert") {
                Task { await viewModel.queueTrackNext(track) }
            }
            Button("Play Later", systemImage: "text.append") {
                Task { await viewModel.queueTrackLater(track) }
            }
        }
    }

    // MARK: - Metadata Sections

    @ViewBuilder
    private var metadataSections: some View {
        if let review = viewModel.review {
            sectionCard(title: "Review") {
                let token = AlbumDetailTypography.token(for: .reviewBody)
                let uiFont = UIFont(name: token.preferredFontName, size: token.size)
                    ?? UIFont.systemFont(ofSize: token.size)
                SelectableText(
                    text: review,
                    font: uiFont,
                    textColor: UIColor(viewModel.palette.textPrimary)
                )
            }
        }

        if !viewModel.genres.isEmpty {
            tagSection(title: "Genres", tags: viewModel.genres, kind: .genre)
        }

        if !viewModel.styles.isEmpty {
            tagSection(title: "Styles", tags: viewModel.styles, kind: .style)
        }

        if !viewModel.moods.isEmpty {
            tagSection(title: "Moods", tags: viewModel.moods, kind: .mood)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(sectionHeadingFont())
                .foregroundStyle(viewModel.palette.textPrimary)
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)
            content()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.palette.background.opacity(0.6))
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)
        }
    }

    private func tagSection(title: String, tags: [String], kind: LibraryTagKind) -> some View {
        sectionCard(title: title) {
            AlbumTagFlowLayout(
                spacing: AlbumDetailLayout.pillHorizontalSpacing,
                rowSpacing: AlbumDetailLayout.pillVerticalSpacing
            ) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        switch kind {
                        case .genre:
                            tagFilterNavigation = TagFilterNavigation(genres: [tag], styles: [], moods: [])
                        case .style:
                            tagFilterNavigation = TagFilterNavigation(genres: [], styles: [tag], moods: [])
                        case .mood:
                            tagFilterNavigation = TagFilterNavigation(genres: [], styles: [], moods: [tag])
                        }
                    } label: {
                        Text(tag)
                            .font(AlbumDetailTypography.font(for: .pill))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(viewModel.palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.palette.textPrimary.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private var metadataText: String {
        var parts: [String] = []
        if let year = viewModel.album.year {
            parts.append(String(year))
        }
        let trackCount = viewModel.tracks.isEmpty ? viewModel.album.trackCount : viewModel.tracks.count
        let duration = viewModel.tracks.isEmpty ? viewModel.album.duration : viewModel.tracks.reduce(0) { $0 + max(0, $1.duration) }
        parts.append("\(trackCount) \(trackCount == 1 ? "track" : "tracks")")
        parts.append(AlbumTrackPresentation.albumDuration(duration))
        return parts.joined(separator: " • ")
    }

    private func sectionHeadingFont() -> Font {
        let token = LunaraVisualTokens.headingToken(for: .section, weight: .semibold)
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(token.preferredFontName, size: token.size, relativeTo: token.relativeTextStyle)
        }
        return .system(size: token.size, weight: token.fallbackWeight, design: .serif)
    }

    private func titleHeadingFont() -> Font {
        let token = LunaraVisualTokens.headingToken(for: .title, weight: .semibold)
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(token.preferredFontName, size: token.size, relativeTo: token.relativeTextStyle)
        }
        return .system(size: token.size, weight: token.fallbackWeight, design: .serif)
    }
}
