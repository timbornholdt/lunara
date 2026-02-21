import SwiftUI
import UIKit

struct ArtistDetailView: View {
    @State private var viewModel: ArtistDetailViewModel
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
                albumsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
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
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerArtwork
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            Text(viewModel.artist.name)
                .font(titleHeadingFont())
                .foregroundStyle(Color.lunara(.textPrimary))

            HStack(spacing: 8) {
                if let genre = viewModel.artist.genre {
                    Text(genre)
                        .font(subtitleFont())
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.lunara(.backgroundBase), in: Capsule())
                }

                Text("\(viewModel.artist.albumCount) \(viewModel.artist.albumCount == 1 ? "album" : "albums")")
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textSecondary))
            }

            if let summary = viewModel.artist.summary,
               !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary)
                        .font(subtitleFont())
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .lineLimit(isBioExpanded ? nil : 3)

                    Button(isBioExpanded ? "Show less" : "Read more") {
                        withAnimation {
                            isBioExpanded.toggle()
                        }
                    }
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textPrimary))
                }
            }

            HStack(spacing: 12) {
                Button("Play All") {
                    Task { await viewModel.playAll() }
                }
                .buttonStyle(LunaraPillButtonStyle())

                Button("Shuffle") {
                    Task { await viewModel.shuffle() }
                }
                .buttonStyle(LunaraPillButtonStyle(role: .secondary))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lunara(.backgroundElevated))
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
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.albums) { album in
                        albumCard(for: album)
                    }
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
                    albumArtworkView(for: album)

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
