import SwiftUI

struct AlbumDetailView: View {
    @State private var viewModel: AlbumDetailViewModel

    init(viewModel: AlbumDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                trackList
                metadataSections
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(viewModel.album.title)
        .navigationBarTitleDisplayMode(.inline)
        .lunaraLinenBackground()
        .lunaraErrorBanner(using: viewModel.errorBannerState)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            Text(viewModel.album.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.lunara(.textPrimary))

            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(Color.lunara(.textSecondary))

            Button("Play Album") {
                Task {
                    await viewModel.playAlbum()
                }
            }
            .buttonStyle(LunaraPillButtonStyle())
        }
        .padding(14)
        .background(Color.lunara(.backgroundElevated), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") {
                Task {
                    await viewModel.queueAlbumNext()
                }
            }
            Button("Play Later", systemImage: "text.append") {
                Task {
                    await viewModel.queueAlbumLater()
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
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
                Image(systemName: "opticaldisc")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tracks")
                .font(.headline)
                .foregroundStyle(Color.lunara(.textPrimary))

            switch viewModel.loadingState {
            case .idle, .loading:
                ProgressView("Loading tracks...")
                    .padding(.vertical, 12)
            case .error(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.lunara(.textSecondary))
            case .loaded:
                if viewModel.tracks.isEmpty {
                    Text("No tracks available for this album.")
                        .font(.subheadline)
                        .foregroundStyle(Color.lunara(.textSecondary))
                } else {
                    ForEach(viewModel.tracks) { track in
                        trackRow(track)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.lunara(.backgroundElevated), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func trackRow(_ track: Track) -> some View {
        Button {
            Task {
                await viewModel.playTrackNow(track)
            }
        } label: {
            HStack(spacing: 10) {
                Text("\(track.trackNumber)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .frame(width: 24, alignment: .trailing)

                Text(track.title)
                    .font(.body)
                    .foregroundStyle(Color.lunara(.textPrimary))
                    .lineLimit(1)

                Spacer()

                Text(track.formattedDuration)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Now", systemImage: "play.fill") {
                Task {
                    await viewModel.playTrackNow(track)
                }
            }
            Button("Play Next", systemImage: "text.insert") {
                Task {
                    await viewModel.queueTrackNext(track)
                }
            }
            Button("Play Later", systemImage: "text.append") {
                Task {
                    await viewModel.queueTrackLater(track)
                }
            }
        }
    }

    @ViewBuilder
    private var metadataSections: some View {
        if let review = viewModel.review {
            sectionCard(title: "Review") {
                Text(review)
                    .font(.body)
                    .foregroundStyle(Color.lunara(.textPrimary))
            }
        }

        if !viewModel.genres.isEmpty {
            tagSection(title: "Genres", tags: viewModel.genres)
        }

        if !viewModel.styles.isEmpty {
            tagSection(title: "Styles", tags: viewModel.styles)
        }

        if !viewModel.moods.isEmpty {
            tagSection(title: "Moods", tags: viewModel.moods)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.lunara(.textPrimary))
            content()
        }
        .padding(14)
        .background(Color.lunara(.backgroundElevated), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tagSection(title: String, tags: [String]) -> some View {
        sectionCard(title: title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.lunara(.backgroundBase), in: Capsule())
                }
            }
        }
    }

    private var subtitleText: String {
        var parts: [String] = [viewModel.album.artistName]
        if let year = viewModel.album.year {
            parts.append(String(year))
        }
        parts.append("\(viewModel.album.trackCount) tracks")
        parts.append(viewModel.album.formattedDuration)
        return parts.joined(separator: " • ")
    }
}
