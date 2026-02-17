import Foundation
import os

struct AlbumDuplicateDebugReporter {
    func logReport(
        albums: [Album],
        logger: Logger,
        spotlightTitle: String? = nil,
        spotlightArtist: String? = nil
    ) {
        let report = makeReport(
            albums: albums,
            spotlightTitle: spotlightTitle,
            spotlightArtist: spotlightArtist
        )

        print(report)
        logger.info("\(report, privacy: .public)")
    }

    func makeReport(
        albums: [Album],
        spotlightTitle: String? = nil,
        spotlightArtist: String? = nil
    ) -> String {
        let exactGroups = groupDuplicates(
            albums: albums,
            keyBuilder: { album in
                "\(normalize(album.artistName))|\(normalize(album.title))|\(album.year?.description ?? "")"
            }
        )

        let candidateGroups = groupDuplicates(
            albums: albums,
            keyBuilder: { album in
                "\(normalize(album.artistName))|\(normalize(album.title))"
            }
        )

        let spotlightMatches = albums.filter { album in
            if let spotlightTitle, !normalize(album.title).contains(normalize(spotlightTitle)) {
                return false
            }

            if let spotlightArtist, !normalize(album.artistName).contains(normalize(spotlightArtist)) {
                return false
            }

            return true
        }.sorted(by: albumSort)

        var lines: [String] = []
        lines.append("========== LUNARA DUPLICATE ALBUM DEBUG REPORT ==========")
        lines.append("Album count: \(albums.count)")
        lines.append("Exact duplicate groups (artist + title + year): \(exactGroups.count)")

        if exactGroups.isEmpty {
            lines.append("  none")
        } else {
            lines.append(contentsOf: describe(groups: exactGroups))
        }

        lines.append("Candidate duplicate groups (artist + title, year ignored): \(candidateGroups.count)")
        if candidateGroups.isEmpty {
            lines.append("  none")
        } else {
            lines.append(contentsOf: describe(groups: candidateGroups))
        }

        if spotlightTitle != nil || spotlightArtist != nil {
            lines.append("Spotlight matches:")
            if spotlightMatches.isEmpty {
                lines.append("  none")
            } else {
                for album in spotlightMatches {
                    lines.append("  - \(albumLine(album))")
                }
            }
        }

        lines.append("========================================================")
        return lines.joined(separator: "\n")
    }

    private func groupDuplicates(
        albums: [Album],
        keyBuilder: (Album) -> String
    ) -> [[Album]] {
        let grouped = Dictionary(grouping: albums, by: keyBuilder)
        return grouped.values
            .filter { $0.count > 1 }
            .map { $0.sorted(by: albumSort) }
            .sorted { lhs, rhs in
                guard let lhsFirst = lhs.first, let rhsFirst = rhs.first else {
                    return lhs.count > rhs.count
                }
                return albumSort(lhsFirst, rhsFirst)
            }
    }

    private func describe(groups: [[Album]]) -> [String] {
        var lines: [String] = []

        for (index, group) in groups.enumerated() {
            guard let first = group.first else {
                continue
            }

            lines.append("  [\(index + 1)] \(first.artistName) - \(first.title) (\(group.count) entries)")
            for album in group {
                lines.append("      - \(albumLine(album))")
            }
        }

        return lines
    }

    private func albumLine(_ album: Album) -> String {
        "id=\(album.plexID), year=\(album.year.map(String.init) ?? "nil"), trackCount=\(album.trackCount), duration=\(Int(album.duration))s"
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func albumSort(_ lhs: Album, _ rhs: Album) -> Bool {
        if lhs.artistName != rhs.artistName {
            return lhs.artistName.localizedCaseInsensitiveCompare(rhs.artistName) == .orderedAscending
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        if lhs.year != rhs.year {
            return (lhs.year ?? Int.min) < (rhs.year ?? Int.min)
        }
        return lhs.plexID < rhs.plexID
    }
}
