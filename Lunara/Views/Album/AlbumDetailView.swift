import SwiftUI

struct AlbumDetailView: View {
    @State private var viewModel: AlbumDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AlbumDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlbumDetailLayout.sectionSpacing) {
                    backButtonRow
                    headerCard
                    trackList
                    metadataSections
                }
                .padding(.horizontal, AlbumDetailLayout.horizontalPadding)
                .padding(.top, AlbumDetailLayout.topContentPadding)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.lunara(.backgroundBase).ignoresSafeArea())
        .lunaraLinenBackground()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lunaraErrorBanner(using: viewModel.errorBannerState)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var backButtonRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.lunara(.textPrimary))
                    .frame(width: 56, height: 56)
                    .background(Color.lunara(.backgroundElevated), in: Circle())
            }
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.top, AlbumDetailLayout.backButtonInsetTop)
        .padding(.bottom, AlbumDetailLayout.backButtonInsetBottom)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            Text(viewModel.album.title)
                .lunaraHeading(.title, weight: .semibold)

            Text(subtitleText)
                .font(AlbumDetailTypography.font(for: .subtitleMetadata))
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
                .lunaraHeading(.section, weight: .semibold)

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
                    .font(AlbumDetailTypography.font(for: .trackNumber))
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .frame(width: 24, alignment: .trailing)

                Text(track.title)
                    .font(AlbumDetailTypography.font(for: .trackTitle))
                    .foregroundStyle(Color.lunara(.textPrimary))
                    .lineLimit(1)

                Spacer()

                Text(track.formattedDuration)
                    .font(AlbumDetailTypography.font(for: .trackDuration))
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
                    .font(AlbumDetailTypography.font(for: .reviewBody))
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
                .lunaraHeading(.section, weight: .semibold)
            content()
        }
        .padding(14)
        .background(Color.lunara(.backgroundElevated), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tagSection(title: String, tags: [String]) -> some View {
        sectionCard(title: title) {
            AlbumTagFlowLayout(
                spacing: AlbumDetailLayout.pillHorizontalSpacing,
                rowSpacing: AlbumDetailLayout.pillVerticalSpacing
            ) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(AlbumDetailTypography.font(for: .pill))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
