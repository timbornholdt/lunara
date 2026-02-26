import SwiftUI
import UIKit

struct TagFilterView: View {
    @State private var viewModel: TagFilterViewModel
    @Environment(\.showNowPlaying) private var showNowPlaying
    @State private var selectedAlbum: Album?
    @State private var genresExpanded = false
    @State private var stylesExpanded = false
    @State private var moodsExpanded = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 16)
    ]

    init(viewModel: TagFilterViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterHeader
                tagSections
                resultsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .lunaraLinenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Browse by Tag")
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

    // MARK: - Filter Header

    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.filterDescription)
                .font(titleHeadingFont())
                .foregroundStyle(Color.lunara(.textPrimary))

            if viewModel.hasActiveFilters {
                Text("\(viewModel.albums.count) \(viewModel.albums.count == 1 ? "album" : "albums")")
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textSecondary))
            }

            if !viewModel.albums.isEmpty {
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
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lunara(.backgroundElevated))
        }
    }

    // MARK: - Tag Sections

    private var tagSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.availableGenres.isEmpty {
                tagSection(
                    title: "Genres",
                    tags: viewModel.availableGenres,
                    selected: viewModel.selectedGenres,
                    isExpanded: $genresExpanded,
                    toggle: { viewModel.toggleGenre($0) }
                )
            }

            if !viewModel.availableStyles.isEmpty {
                tagSection(
                    title: "Styles",
                    tags: viewModel.availableStyles,
                    selected: viewModel.selectedStyles,
                    isExpanded: $stylesExpanded,
                    toggle: { viewModel.toggleStyle($0) }
                )
            }

            if !viewModel.availableMoods.isEmpty {
                tagSection(
                    title: "Moods",
                    tags: viewModel.availableMoods,
                    selected: viewModel.selectedMoods,
                    isExpanded: $moodsExpanded,
                    toggle: { viewModel.toggleMood($0) }
                )
            }
        }
    }

    private func tagSection(
        title: String,
        tags: [String],
        selected: Set<String>,
        isExpanded: Binding<Bool>,
        toggle: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(sectionHeadingFont())
                        .foregroundStyle(Color.lunara(.textPrimary))
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                AlbumTagFlowLayout(
                    spacing: AlbumDetailLayout.pillHorizontalSpacing,
                    rowSpacing: AlbumDetailLayout.pillVerticalSpacing
                ) {
                    ForEach(tags, id: \.self) { tag in
                        tagPill(tag, isSelected: selected.contains(tag)) {
                            toggle(tag)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lunara(.backgroundElevated))
        }
    }

    private func tagPill(_ tag: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(tag)
                .font(pillFont())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? Color.lunara(.backgroundBase) : Color.lunara(.textPrimary))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.lunara(.textPrimary) : Color.lunara(.textPrimary).opacity(0.15),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        switch viewModel.loadingState {
        case .idle:
            EmptyView()
        case .loading:
            VStack {
                Spacer()
                ProgressView("Loading...")
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
            if viewModel.hasActiveFilters && viewModel.albums.isEmpty {
                Text("No albums match the selected filters.")
                    .font(subtitleFont())
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .padding(.top, 8)
            } else if !viewModel.albums.isEmpty {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.albums) { album in
                        albumCard(for: album)
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
    }

    @ViewBuilder
    private func albumArtworkView(for album: Album) -> some View {
        let thumbnailURL = viewModel.albumThumbnailURL(for: album.plexID)

        ZStack {
            Color.lunara(.backgroundBase)

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

    private func sectionHeadingFont() -> Font {
        let token = LunaraVisualTokens.headingToken(for: .section, weight: .semibold)
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

    private func pillFont() -> Font {
        let size: CGFloat = 14
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .caption)
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
