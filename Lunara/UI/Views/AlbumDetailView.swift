import SwiftUI

struct AlbumDetailView: View {
    let album: PlexAlbum
    @StateObject private var viewModel: AlbumDetailViewModel

    init(album: PlexAlbum) {
        self.album = album
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AlbumArtworkView(album: album)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.title)
                            .font(.title2)
                        if let year = album.year {
                            Text(String(year))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if viewModel.isLoading {
                ProgressView("Loading tracks...")
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                Section("Tracks") {
                    ForEach(viewModel.tracks, id: \.ratingKey) { track in
                        HStack {
                            Text(track.index.map(String.init) ?? "-")
                                .foregroundStyle(.secondary)
                            Text(track.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Album")
        .task {
            await viewModel.loadTracks()
        }
    }
}
