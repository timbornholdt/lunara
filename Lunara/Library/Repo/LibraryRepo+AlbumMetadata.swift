import Foundation

extension LibraryRepo {
    func dedupeLibrary(albums: [Album], tracks: [Track]) -> DedupeResult {
        var groups: [String: DedupeGroup] = [:]
        var albumIDsByGroupKey: [String: [String]] = [:]

        for album in albums {
            let key = dedupeKey(for: album)
            if let existingGroup = groups[key] {
                let canonicalAlbum = canonicalAlbum(between: existingGroup.canonicalAlbum, and: album)
                groups[key]?.canonicalAlbum = canonicalAlbum
                albumIDsByGroupKey[key, default: []].append(album.plexID)
                continue
            }

            groups[key] = DedupeGroup(canonicalAlbum: album, tracksByID: [:])
            albumIDsByGroupKey[key] = [album.plexID]
        }

        var albumIDToGroupKey: [String: String] = [:]
        for (groupKey, albumIDs) in albumIDsByGroupKey {
            for albumID in albumIDs {
                albumIDToGroupKey[albumID] = groupKey
            }
        }

        for track in tracks {
            guard let groupKey = albumIDToGroupKey[track.albumID] else {
                continue
            }
            guard let group = groups[groupKey] else {
                continue
            }

            let canonicalAlbumID = group.canonicalAlbum.plexID
            let canonicalTrack = Track(
                plexID: track.plexID,
                albumID: canonicalAlbumID,
                title: track.title,
                trackNumber: track.trackNumber,
                duration: track.duration,
                artistName: track.artistName,
                key: track.key,
                thumbURL: track.thumbURL
            )
            groups[groupKey]?.tracksByID[track.plexID] = canonicalTrack
        }

        let sortedGroupKeys = groups.keys.sorted()
        var dedupedAlbums: [Album] = []
        var dedupedTracks: [Track] = []

        dedupedAlbums.reserveCapacity(groups.count)
        dedupedTracks.reserveCapacity(tracks.count)

        for groupKey in sortedGroupKeys {
            guard let group = groups[groupKey] else {
                continue
            }

            let mergedTracks = group.tracksByID.values.sorted {
                if $0.trackNumber != $1.trackNumber {
                    return $0.trackNumber < $1.trackNumber
                }
                if $0.title != $1.title {
                    return $0.title < $1.title
                }
                return $0.plexID < $1.plexID
            }

            let mergedDuration = mergedTracks.reduce(0) { $0 + max(0, $1.duration) }
            let mergedAlbum = Album(
                plexID: group.canonicalAlbum.plexID,
                title: group.canonicalAlbum.title,
                artistName: group.canonicalAlbum.artistName,
                year: group.canonicalAlbum.year,
                releaseDate: group.canonicalAlbum.releaseDate,
                thumbURL: group.canonicalAlbum.thumbURL,
                genre: group.canonicalAlbum.genre,
                rating: group.canonicalAlbum.rating,
                addedAt: group.canonicalAlbum.addedAt,
                trackCount: max(group.canonicalAlbum.trackCount, mergedTracks.count),
                duration: max(group.canonicalAlbum.duration, mergedDuration),
                review: group.canonicalAlbum.review,
                genres: group.canonicalAlbum.genres,
                styles: group.canonicalAlbum.styles,
                moods: group.canonicalAlbum.moods
            )

            dedupedAlbums.append(mergedAlbum)
            dedupedTracks.append(contentsOf: mergedTracks)
        }

        return DedupeResult(albums: dedupedAlbums, tracks: dedupedTracks)
    }

    func dedupeKey(for album: Album) -> String {
        "\(normalizeForDedupe(album.artistName))|\(normalizeForDedupe(album.title))|\(album.year?.description ?? "")"
    }

    func normalizeForDedupe(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func canonicalAlbum(between lhs: Album, and rhs: Album) -> Album {
        if lhs.plexID <= rhs.plexID {
            return mergeAlbumMetadata(primary: lhs, fallback: rhs)
        }
        return mergeAlbumMetadata(primary: rhs, fallback: lhs)
    }

    func mergeAlbumMetadata(primary: Album, fallback: Album) -> Album {
        Album(
            plexID: primary.plexID,
            title: primary.title,
            artistName: primary.artistName,
            year: primary.year ?? fallback.year,
            releaseDate: primary.releaseDate ?? fallback.releaseDate,
            thumbURL: primary.thumbURL ?? fallback.thumbURL,
            genre: primary.genre ?? fallback.genre,
            rating: primary.rating ?? fallback.rating,
            addedAt: primary.addedAt ?? fallback.addedAt,
            trackCount: max(primary.trackCount, fallback.trackCount),
            duration: max(primary.duration, fallback.duration),
            review: primary.review ?? fallback.review,
            genres: mergeTags(primary.genres, fallback.genres),
            styles: mergeTags(primary.styles, fallback.styles),
            moods: mergeTags(primary.moods, fallback.moods)
        )
    }

    func mergeTags(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for tag in lhs + rhs {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }
            merged.append(normalized)
        }
        return merged
    }

    func preloadThumbnailArtwork(for albums: [Album]) async {
        for album in albums {
            do {
                let sourceURL = try await remote.authenticatedArtworkURL(for: album.thumbURL)
                _ = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                )
            } catch {
                // Artwork warmup is best-effort so metadata refresh remains available when image fetch fails.
                continue
            }
        }
    }

    func reconcileThumbnailArtwork(
        cachedAlbumsByID: [String: Album],
        refreshedAlbums: [Album],
        deletedAlbumIDs: [String]
    ) async {
        var invalidatedAlbumIDs = Set<String>()

        for albumID in deletedAlbumIDs {
            do {
                try await artworkPipeline.invalidateCache(for: albumID, ownerKind: .album)
                invalidatedAlbumIDs.insert(albumID)
            } catch {
                continue
            }
        }

        for album in refreshedAlbums {
            let previousAlbum = cachedAlbumsByID[album.plexID]
            let thumbnailChanged: Bool
            if let previousAlbum {
                thumbnailChanged = normalizedArtworkReference(previousAlbum.thumbURL) != normalizedArtworkReference(album.thumbURL)
            } else {
                thumbnailChanged = false
            }

            if thumbnailChanged && !invalidatedAlbumIDs.contains(album.plexID) {
                do {
                    try await artworkPipeline.invalidateCache(for: album.plexID, ownerKind: .album)
                    invalidatedAlbumIDs.insert(album.plexID)
                } catch {
                    continue
                }
            }

            do {
                if try await shouldWarmThumbnail(
                    for: album.plexID,
                    thumbURL: album.thumbURL,
                    forceWarm: thumbnailChanged || previousAlbum == nil
                ) {
                    let sourceURL = try await remote.authenticatedArtworkURL(for: album.thumbURL)
                    _ = try await artworkPipeline.fetchThumbnail(
                        for: album.plexID,
                        ownerKind: .album,
                        sourceURL: sourceURL
                    )
                }
            } catch {
                continue
            }
        }
    }

    private func shouldWarmThumbnail(for albumID: String, thumbURL: String?, forceWarm: Bool) async throws -> Bool {
        guard let normalizedThumb = normalizedArtworkReference(thumbURL), !normalizedThumb.isEmpty else {
            return false
        }

        if forceWarm {
            return true
        }

        let key = ArtworkKey(ownerID: albumID, ownerType: .album, variant: .thumbnail)
        guard let cachedPath = try await store.artworkPath(for: key) else {
            return true
        }

        return !FileManager.default.fileExists(atPath: cachedPath)
    }

    private func normalizedArtworkReference(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
