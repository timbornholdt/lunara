import SwiftUI
import UIKit

struct CollectionDetailView: View {
    @State private var viewModel: CollectionDetailViewModel
    @Environment(\.showNowPlaying) private var showNowPlaying
    @State private var selectedAlbum: Album?
    /// Delay-gates the loading skeleton: collectionAlbums is offline-first SQLite
    /// and usually returns in well under 200ms, so the common path renders the real
    /// grid directly with no loading UI at all (Lunara-uwc).
    @State private var showLoadingPlaceholder = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)
    ]

    init(viewModel: CollectionDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                albumsSection
                    // Group-opacity crossfade skeleton → grid (no per-cell pops).
                    .animation(.easeInOut(duration: 0.3), value: viewModel.loadingState)
                collectionSyncButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .lunaraLinenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.collection.title)
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

            Text(viewModel.collection.title)
                .font(titleHeadingFont())
                .foregroundStyle(Color.lunara(.textPrimary))

            Text(viewModel.collection.subtitle)
                .font(subtitleFont())
                .foregroundStyle(Color.lunara(.textSecondary))

            if let summary = viewModel.collection.summary,
               !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(summary)
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textSecondary))
            }

            HStack(spacing: 12) {
                Button("Play All") {
                    Task {
                        await viewModel.playAll()
                        showNowPlaying.wrappedValue = true
                    }
                }
                .buttonStyle(LunaraPillButtonStyle())

                Button("Shuffle") {
                    Task {
                        await viewModel.shuffle()
                        showNowPlaying.wrappedValue = true
                    }
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
                Image(systemName: "rectangle.stack")
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
            skeletonGrid
                .opacity(showLoadingPlaceholder ? 1 : 0)
                .task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    showLoadingPlaceholder = true
                }
        case .error(let message):
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.lunara(.accentPrimary))
                Text(message)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .multilineTextAlignment(.center)
                Spacer()
            }
        case .loaded:
            if viewModel.albums.isEmpty {
                Text("No albums in this collection.")
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

    /// Static placeholder cards in the SAME grid geometry as the loaded grid, so
    /// the header and the button below it don't jump when content arrives. Sized
    /// by the collection's known album count, capped at one screenful.
    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(0..<min(max(viewModel.collection.albumCount, 1), 8), id: \.self) { _ in
                LunaraSkeleton()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading albums")
        .animation(.easeInOut(duration: 0.2), value: showLoadingPlaceholder)
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

                    Text(album.subtitle)
                        .font(albumSubtitleFont)
                        .lineLimit(2)
                        .foregroundStyle(Color.lunara(.textSecondary))
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

    // MARK: - Download Button

    @ViewBuilder
    private var collectionSyncButton: some View {
        switch viewModel.syncState {
        case .idle:
            Button {
                Task { await viewModel.toggleSync() }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Keep Downloaded")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(Color.lunara(.textSecondary))
            }

        case .syncing(let current, let total):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing... \(current)/\(total) albums")
                    .font(.subheadline)
                    .foregroundStyle(Color.lunara(.textSecondary))
                Spacer()
                Text("\(current)/\(total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.lunara(.textSecondary))
            }

        case .synced:
            Menu {
                Button("Stop Syncing", role: .destructive) {
                    Task { await viewModel.stopSyncing() }
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Synced")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(Color.lunara(.textSecondary))
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(message)
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.red)

                Button("Retry") {
                    Task { await viewModel.toggleSync() }
                }
                .font(.subheadline)
                .foregroundStyle(Color.lunara(.textSecondary))
            }
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
