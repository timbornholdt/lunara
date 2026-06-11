import Foundation
import Observation

@MainActor
@Observable
final class ArtistDetailViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let artist: Artist
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: ArtistsListActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let gardenClient: GardenAPIClientProtocol?

    var albums: [Album] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkURL: URL?
    var artworkByAlbumID: [String: URL] = [:]
    private(set) var lastFMBio: String?

    /// Plex's own summary when it has one; otherwise the Last.fm bio fallback.
    var displayBio: String? {
        if let summary = artist.summary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        return lastFMBio
    }

    private(set) var externalLinks: MusicBrainzArtistEnrichment?
    private(set) var missingAlbums: [ExternalReleaseGroup] = []
    private(set) var upcomingConcerts: [ConcertEvent] = []

    private var pendingArtworkAlbumIDs: Set<String> = []
    private var hasRequestedLastFMBio = false
    private var hasRequestedEnrichment = false
    private var hasRequestedConcerts = false

    init(
        artist: Artist,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: ArtistsListActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        gardenClient: GardenAPIClientProtocol? = nil
    ) {
        self.artist = artist
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.gardenClient = gardenClient
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        loadingState = .loading
        await loadAlbums()
        await loadArtistArtwork()
    }

    /// Enrichment older than this re-fetches on the next page visit; younger is
    /// served from the cache alone (Lunara-ya7). Bios never expire.
    static let enrichmentTTL: TimeInterval = 7 * 24 * 3600

    /// Resolves the Last.fm bio once, and only for artists whose Plex summary
    /// is blank — Plex's own text always wins (Lunara-uww.6.1). Cached bios
    /// serve without a network call (Lunara-ya7).
    func loadLastFMBioIfNeeded(using client: LastFMClientProtocol?) async {
        guard !hasRequestedLastFMBio else { return }
        guard displayBio == nil else { return }
        hasRequestedLastFMBio = true

        if let cachedBio = (try? await library.cachedArtistEnrichment(name: artist.name))??.lastFMBio {
            lastFMBio = cachedBio
            return
        }

        guard let client else { return }
        lastFMBio = try? await client.getArtistBio(artist: artist.name)
        if let lastFMBio {
            try? await library.saveArtistLastFMBio(lastFMBio, name: artist.name)
        }
    }

    /// MusicBrainz links + studio discography, cache-first: the persisted copy
    /// renders instantly (and offline), then a fetch refreshes it when older
    /// than `enrichmentTTL` (Lunara-ya7). Call after `loadIfNeeded` so the
    /// loaded albums are available to match against (Lunara-uww.6.2 / 6.3).
    func loadEnrichmentIfNeeded(using client: MusicBrainzClientProtocol?) async {
        guard !hasRequestedEnrichment else { return }
        hasRequestedEnrichment = true

        let cached = try? await library.cachedArtistEnrichment(name: artist.name)
        if let cachedEnrichment = cached?.enrichment {
            apply(cachedEnrichment)
        }

        let isFresh = cached.flatMap { entry in
            entry.enrichment == nil ? nil : entry.fetchedAt
        }.map { Date().timeIntervalSince($0) < Self.enrichmentTTL } ?? false
        guard !isFresh, let client else { return }

        guard let enrichment = ((try? await client.artistEnrichment(name: artist.name)) ?? nil) else {
            return
        }
        apply(enrichment)
        try? await library.saveArtistEnrichment(enrichment, name: artist.name)
    }

    private func apply(_ enrichment: MusicBrainzArtistEnrichment) {
        externalLinks = enrichment

        let libraryTitles = Set(albums.map { Self.normalizedTitle($0.title) })
        // Newest releases first (unknown years last) — fresh albums you don't
        // own yet are the point of the section (Lunara-c9w).
        missingAlbums = enrichment.albums
            .filter { !libraryTitles.contains(Self.normalizedTitle($0.title)) }
            .sorted { ($0.firstReleaseYear ?? Int.min) > ($1.firstReleaseYear ?? Int.min) }
    }

    /// Casefolded, diacritic-insensitive, alphanumerics-only — so "One Chord To
    /// Another!" matches "one chord to another" across catalogs.
    private static func normalizedTitle(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Fetches upcoming nearby shows once per VM (Lunara-uww.6.4). Best-effort:
    /// failures or a missing API key just leave the section hidden.
    func loadConcertsIfNeeded(using client: TicketmasterClientProtocol?) async {
        guard let client, !hasRequestedConcerts else { return }
        hasRequestedConcerts = true
        upcomingConcerts = (try? await client.upcomingEvents(artistName: artist.name)) ?? []
    }

    func playAll() async {
        await runAction {
            try await actions.playArtist(artist)
        }
    }

    func shuffle() async {
        await runAction {
            try await actions.shuffleArtist(artist)
        }
    }

    func playAlbum(_ album: Album) async {
        await runAction {
            try await actions.playAlbum(album)
        }
    }

    func queueAlbumNext(_ album: Album) async {
        await runAction {
            try await actions.queueAlbumNext(album)
        }
    }

    func queueAlbumLater(_ album: Album) async {
        await runAction {
            try await actions.queueAlbumLater(album)
        }
    }

    func makeAlbumDetailViewModel(for album: Album) -> AlbumDetailViewModel {
        AlbumDetailViewModel(
            album: album,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
            downloadManager: downloadManager,
            gardenClient: gardenClient,
            review: album.review,
            genres: album.genres.isEmpty ? nil : album.genres,
            styles: album.styles,
            moods: album.moods
        )
    }

    func albumThumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadAlbumThumbnailIfNeeded(for album: Album) {
        guard albumThumbnailURL(for: album.plexID) == nil else {
            return
        }

        guard pendingArtworkAlbumIDs.insert(album.plexID).inserted else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceURL = try await library.authenticatedThumbnailURL(for: album.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                ) {
                    self.artworkByAlbumID[album.plexID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking; leave placeholder visible when fetch fails.
            }

            self.pendingArtworkAlbumIDs.remove(album.plexID)
        }
    }

    private func loadAlbums() async {
        do {
            albums = try await library.artistAlbums(artistName: artist.name)
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func loadArtistArtwork() async {
        do {
            let sourceURL = try await library.authenticatedArtworkURL(for: artist.thumbURL)
            artworkURL = try await artworkPipeline.fetchFullSize(
                for: artist.plexID,
                ownerKind: .artist,
                sourceURL: sourceURL
            )
        } catch {
            // Artwork is non-blocking for detail presentation.
        }
    }

    private func runAction(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let lunaraError = error as? LunaraError {
            return lunaraError.userMessage
        }
        return error.localizedDescription
    }
}
