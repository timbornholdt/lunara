import SwiftUI

/// Release radar (Lunara-nlo): upcoming albums from artists with a 4.5★+
/// album, soonest first. Rows link out to the MusicBrainz release group.
struct RadarView: View {
    let service: RadarService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if service.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(service.entries) { entry in
                        radarRow(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("Release Radar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.lunara(.backgroundBase), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .lunaraLinenBackground()
        .task {
            await service.loadCached()
            await service.refreshIfStale()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing on the radar yet.")
                .font(serifFont(size: 16))
                .foregroundStyle(Color.lunara(.textPrimary))
            Text("Albums announced by artists you've rated 4.5 stars or higher will appear here as MusicBrainz learns about them.")
                .font(serifFont(size: 14))
                .foregroundStyle(Color.lunara(.textSecondary))
        }
        .padding(.top, 12)
    }

    private func radarRow(_ entry: RadarEntry) -> some View {
        Link(destination: entry.musicBrainzURL) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(serifFont(size: 16))
                        .foregroundStyle(Color.lunara(.textPrimary))
                        .lineLimit(2)
                    Text(entry.artistName)
                        .font(serifFont(size: 14))
                        .foregroundStyle(Color.lunara(.textSecondary))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.firstReleaseDate)
                        .font(serifFont(size: 14))
                        .foregroundStyle(Color.lunara(.textSecondary))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.lunara(.backgroundElevated))
            }
        }
    }

    private func serifFont(size: CGFloat) -> Font {
        if UIFont(name: "PlayfairDisplay-Regular", size: size) != nil {
            return .custom("PlayfairDisplay-Regular", size: size, relativeTo: .body)
        }
        return .system(size: size, design: .serif)
    }
}
