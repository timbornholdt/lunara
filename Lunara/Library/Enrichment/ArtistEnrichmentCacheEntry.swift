import Foundation

/// One artist's cached enrichment row (Lunara-ya7): MusicBrainz links +
/// discography and the Last.fm bio, with the enrichment's fetch time for the
/// stale-while-revalidate check. `enrichment` is nil for bio-only rows.
struct ArtistEnrichmentCacheEntry: Equatable, Sendable {
    let enrichment: MusicBrainzArtistEnrichment?
    let lastFMBio: String?
    let fetchedAt: Date
}
