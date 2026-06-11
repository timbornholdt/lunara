import Foundation
import UIKit

/// Coalesces concurrent calls for the same key onto a single in-flight task and
/// memoizes the result in a bounded LRU. One instance backs each resolver "leg"
/// (track, album, full artwork, thumbnail). Every mutation happens before or
/// after an `await` — never across one — so no `inout`-over-await is needed.
@MainActor
final class CoalescingMemo<Key: Hashable, Value> {
    private let capacity: Int
    private var cache: [Key: Value] = [:]
    private var order: [Key] = []
    private var inFlight: [Key: Task<Value, Never>] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// `shouldCache` decides whether a freshly produced value is memoized. It
    /// defaults to always-cache; callers pass a predicate to AVOID memoizing
    /// failures (e.g. a nil track or a failed artwork decode) so the next caller
    /// re-runs `make` rather than being served a stale negative result — this is
    /// what keeps the lock screen's artwork retry and transient-error recovery alive.
    func value(
        for key: Key,
        shouldCache: @escaping (Value) -> Bool = { _ in true },
        make: @escaping @MainActor (Key) async -> Value
    ) async -> Value {
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        // A concurrent caller already kicked off this key — ride its result.
        if let inFlightTask = inFlight[key] {
            return await inFlightTask.value
        }

        // No await between creating and registering the task, so concurrent
        // callers for the same key always find it instead of starting their own.
        let task = Task { @MainActor in await make(key) }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)

        guard shouldCache(result) else { return result }
        // updateValue (not subscript-assign) so a `nil` Value memoizes a negative
        // result instead of removing the key, when shouldCache opts into it.
        cache.updateValue(result, forKey: key)
        touch(key)
        evictIfNeeded()
        return result
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictIfNeeded() {
        while cache.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    #if DEBUG
    var countForTesting: Int { cache.count }
    #endif
}

/// Shared, deduplicating source for current/next-track display data. Replaces
/// the three copy-pasted `library.track` → `library.album` → artwork chains that
/// the now-playing screen, bar, and lock-screen bridge each ran independently
/// (and the scrobble manager's track/album lookups). Per single track change the
/// work collapses to one `track`, one `album`, and one full-size decode shared
/// across every consumer.
@MainActor
final class NowPlayingResolver {
    struct Art {
        let image: UIImage?
        let palette: ArtworkPaletteTheme
    }

    private let library: LibraryRepoProtocol
    private let artwork: ArtworkPipelineProtocol

    private let trackMemo = CoalescingMemo<String, Track?>(capacity: 8)
    private let albumMemo = CoalescingMemo<String, Album?>(capacity: 8)
    private let thumbMemo = CoalescingMemo<String, URL?>(capacity: 8)
    /// The decoded full-size `UIImage`s are the only real memory cost, so this is
    /// the leg that's tightly bounded: prev + current + next + one prefetch.
    private let artMemo = CoalescingMemo<String, Art>(capacity: 4)
    /// Decoded Up Next row thumbnails. Capacity matches the Up Next window (20) so a
    /// fully-distinct-album window never self-evicts mid-build; at ~58KB per 120px
    /// thumbnail the worst case is ~1.2MB.
    private let thumbArtMemo = CoalescingMemo<String, UIImage?>(capacity: 20)

    /// Max pixel dimension the hero artwork is downsampled to on decode — bounds
    /// the decode cost while staying crisp at the near-full-width display size.
    private static let fullArtMaxPixelSize = 1024
    /// Max pixel dimension for an Up Next row thumbnail (40pt row × scale 3 = 120px).
    private static let thumbnailMaxPixelSize = 120

    init(library: LibraryRepoProtocol, artwork: ArtworkPipelineProtocol) {
        self.library = library
        self.artwork = artwork
    }

    func track(id trackID: String) async -> Track? {
        await trackMemo.value(for: trackID, shouldCache: { $0 != nil }) { [library] id in
            try? await library.track(id: id)
        }
    }

    func album(id albumID: String) async -> Album? {
        await albumMemo.value(for: albumID, shouldCache: { $0 != nil }) { [library] id in
            try? await library.album(id: id)
        }
    }

    /// Full-size decoded hero image + palette for an album. The fetch source URL
    /// is derived internally via `authenticatedArtworkURL`, so every consumer
    /// resolves it the same way (standardizing the lock-screen bridge, which used
    /// to pass a raw URL). Decode + palette extraction run off the main actor.
    func fullArtwork(for album: Album) async -> Art {
        // A failed decode (nil image) must NOT be memoized: the artwork may simply
        // not be downloaded yet, and the bridge retries — a cached nil would defeat it.
        await artMemo.value(for: album.plexID, shouldCache: { $0.image != nil }) { [library, artwork] _ in
            let sourceURL = try? await library.authenticatedArtworkURL(for: album.thumbURL)
            let fileURL = try? await artwork.fetchFullSize(
                for: album.plexID,
                ownerKind: .album,
                sourceURL: sourceURL
            )
            let maxPixelSize = Self.fullArtMaxPixelSize
            return await Task.detached {
                if let fileURL,
                   let image = DownsamplingImageLoader.load(contentsOf: fileURL, maxPixelSize: maxPixelSize) {
                    return Art(image: image, palette: ArtworkPaletteExtractor.extract(from: image))
                }
                return Art(image: nil, palette: .default)
            }.value
        }
    }

    /// Thumbnail file URL (no decode, no palette) for the now-playing bar.
    func thumbnailURL(for album: Album) async -> URL? {
        await thumbMemo.value(for: album.plexID, shouldCache: { $0 != nil }) { [library, artwork] _ in
            let sourceURL = try? await library.authenticatedThumbnailURL(for: album.thumbURL)
            return try? await artwork.fetchThumbnail(
                for: album.plexID,
                ownerKind: .album,
                sourceURL: sourceURL
            )
        }
    }

    /// Decoded, downsampled thumbnail image for an Up Next row. Mirrors `fullArtwork`:
    /// the decode runs off the main actor and the result is memoized per album, so the
    /// same art is read+decoded once and reused across rows (many tracks from one album)
    /// and across window rebuilds, instead of decoding per row.
    func thumbnailArtwork(for album: Album) async -> UIImage? {
        // A nil (failed/not-yet-downloaded) decode must NOT be memoized, so the next
        // caller re-fetches rather than being served a cached miss — same rationale as
        // the full-art and track/album legs.
        await thumbArtMemo.value(for: album.plexID, shouldCache: { $0 != nil }) { [library, artwork] _ in
            let sourceURL = try? await library.authenticatedThumbnailURL(for: album.thumbURL)
            let fileURL = try? await artwork.fetchThumbnail(
                for: album.plexID,
                ownerKind: .album,
                sourceURL: sourceURL
            )
            let maxPixelSize = Self.thumbnailMaxPixelSize
            return await Task.detached {
                guard let fileURL else { return nil }
                return DownsamplingImageLoader.load(contentsOf: fileURL, maxPixelSize: maxPixelSize)
            }.value
        }
    }
}
