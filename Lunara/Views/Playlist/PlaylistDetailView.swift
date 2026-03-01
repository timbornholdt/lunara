import SwiftUI
import UIKit

struct PlaylistDetailView: View {
    @State private var viewModel: PlaylistDetailViewModel
    @Environment(\.showNowPlaying) private var showNowPlaying

    init(viewModel: PlaylistDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                headerSection
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            tracksSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .lunaraLinenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.playlist.title)
                    .lunaraHeading(.section, weight: .semibold)
                    .lineLimit(1)
            }
        }
        .toolbarBackground(Color.lunara(.backgroundBase), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .lunaraErrorBanner(using: viewModel.errorBannerState)
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $viewModel.showGardenSheet) {
            if let track = viewModel.gardenSheetTrack {
                GardenTodoSheet(
                    artistName: track.artistName,
                    albumName: track.title,
                    onSubmit: { body in
                        try await viewModel.submitGardenTodo(body: body)
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.lunara(.backgroundBase))

                if let artworkURL = viewModel.playlistArtworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(viewModel.playlist.title)
                .font(titleHeadingFont())
                .foregroundStyle(Color.lunara(.textPrimary))

            Text(viewModel.playlist.subtitle)
                .font(subtitleFont())
                .foregroundStyle(Color.lunara(.textSecondary))

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

    // MARK: - Tracks

    @ViewBuilder
    private var tracksSection: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            Section {
                ProgressView("Loading tracks...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        case .error(let message):
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.lunara(.accentPrimary))
                    Text(message)
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        case .loaded:
            if viewModel.tracks.isEmpty {
                Section {
                    Text("No tracks in this playlist.")
                        .font(subtitleFont())
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                        trackRow(for: track, at: index)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.lunara(.backgroundElevated))
                    }
                }
            }
        }
    }

    private func trackRow(for track: Track, at index: Int) -> some View {
        Button {
            Task {
                await viewModel.playFromTrack(track)
                showNowPlaying.wrappedValue = true
            }
        } label: {
            HStack(spacing: 12) {
                trackArtworkView(for: track)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(trackTitleFont)
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .lineLimit(1)

                    Text(track.artistName)
                        .font(trackSubtitleFont)
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(trackSubtitleFont)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") {
                Task { await viewModel.queueTrackNext(track) }
            }
            Button("Play Later", systemImage: "text.append") {
                Task { await viewModel.queueTrackLater(track) }
            }
        }
        .swipeActions(edge: .leading) {
            if viewModel.isChoppingBlock {
                Button("Keep") {
                    Task { await viewModel.keepItem(at: index) }
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            if viewModel.isChoppingBlock {
                Button("Remove") {
                    viewModel.removeWithTodo(at: index)
                }
                .tint(.red)
            }
        }
    }

    @ViewBuilder
    private func trackArtworkView(for track: Track) -> some View {
        let thumbnailURL = viewModel.albumThumbnailURL(for: track.albumID)

        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            viewModel.loadAlbumThumbnailIfNeeded(for: track)
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

    private var trackTitleFont: Font {
        let size: CGFloat = 16
        if UIFont(name: "PlayfairDisplay-SemiBold", size: size) != nil {
            return .custom("PlayfairDisplay-SemiBold", size: size, relativeTo: .body)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    private var trackSubtitleFont: Font {
        let size: CGFloat = 14
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .caption)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }
}
