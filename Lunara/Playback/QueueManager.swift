import Foundation

enum QueueInsertMode: String, Codable, Sendable {
    case playNow
    case playNext
    case playLater
}

enum QueueInsertSkipReason: String, Codable, Sendable {
    case missingPlaybackSource
    case missingTrackURL
    case unknown
}

struct QueueEntry: Equatable, Sendable {
    let id: UUID
    let track: PlexTrack
    let album: PlexAlbum?
    let albumRatingKeys: [String]
    let artworkPath: String?
    let isPlayable: Bool
    let skipReason: QueueInsertSkipReason?

    init(
        id: UUID = UUID(),
        track: PlexTrack,
        album: PlexAlbum?,
        albumRatingKeys: [String],
        artworkRequest: ArtworkRequest?,
        isPlayable: Bool,
        skipReason: QueueInsertSkipReason?
    ) {
        self.id = id
        self.track = track
        self.album = album
        self.albumRatingKeys = albumRatingKeys
        self.artworkPath = artworkRequest?.key.artworkPath
        self.isPlayable = isPlayable
        self.skipReason = skipReason
    }
}

extension QueueEntry: Codable {
    private struct PersistedTrack: Codable {
        let ratingKey: String
        let title: String
        let index: Int?
        let parentIndex: Int?
        let parentRatingKey: String?
        let duration: Int?
        let mediaPartKeys: [String]
        let originalTitle: String?
        let grandparentTitle: String?
    }

    private struct PersistedAlbum: Codable {
        let ratingKey: String
        let title: String
        let thumb: String?
        let art: String?
        let year: Int?
        let artist: String?
        let titleSort: String?
        let originalTitle: String?
        let editionTitle: String?
        let guid: String?
        let librarySectionID: Int?
        let parentRatingKey: String?
        let studio: String?
        let summary: String?
        let rating: Double?
        let userRating: Double?
        let key: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case track
        case album
        case albumRatingKeys
        case artworkPath
        case isPlayable
        case skipReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let persistedTrack = try container.decode(PersistedTrack.self, forKey: .track)
        let media: [PlexTrackMedia]? = {
            guard !persistedTrack.mediaPartKeys.isEmpty else { return nil }
            let parts = persistedTrack.mediaPartKeys.map { PlexTrackPart(key: $0) }
            return [PlexTrackMedia(parts: parts)]
        }()
        track = PlexTrack(
            ratingKey: persistedTrack.ratingKey,
            title: persistedTrack.title,
            index: persistedTrack.index,
            parentIndex: persistedTrack.parentIndex,
            parentRatingKey: persistedTrack.parentRatingKey,
            duration: persistedTrack.duration,
            media: media,
            originalTitle: persistedTrack.originalTitle,
            grandparentTitle: persistedTrack.grandparentTitle
        )
        if let persistedAlbum = try container.decodeIfPresent(PersistedAlbum.self, forKey: .album) {
            album = PlexAlbum(
                ratingKey: persistedAlbum.ratingKey,
                title: persistedAlbum.title,
                thumb: persistedAlbum.thumb,
                art: persistedAlbum.art,
                year: persistedAlbum.year,
                artist: persistedAlbum.artist,
                titleSort: persistedAlbum.titleSort,
                originalTitle: persistedAlbum.originalTitle,
                editionTitle: persistedAlbum.editionTitle,
                guid: persistedAlbum.guid,
                librarySectionID: persistedAlbum.librarySectionID,
                parentRatingKey: persistedAlbum.parentRatingKey,
                studio: persistedAlbum.studio,
                summary: persistedAlbum.summary,
                genres: nil,
                styles: nil,
                moods: nil,
                rating: persistedAlbum.rating,
                userRating: persistedAlbum.userRating,
                key: persistedAlbum.key
            )
        } else {
            album = nil
        }
        albumRatingKeys = try container.decode([String].self, forKey: .albumRatingKeys)
        artworkPath = try container.decodeIfPresent(String.self, forKey: .artworkPath)
        isPlayable = try container.decode(Bool.self, forKey: .isPlayable)
        skipReason = try container.decodeIfPresent(QueueInsertSkipReason.self, forKey: .skipReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        let partKeys = track.media?.flatMap(\.parts).map(\.key) ?? []
        try container.encode(
            PersistedTrack(
                ratingKey: track.ratingKey,
                title: track.title,
                index: track.index,
                parentIndex: track.parentIndex,
                parentRatingKey: track.parentRatingKey,
                duration: track.duration,
                mediaPartKeys: partKeys,
                originalTitle: track.originalTitle,
                grandparentTitle: track.grandparentTitle
            ),
            forKey: .track
        )
        if let album {
            try container.encode(
                PersistedAlbum(
                    ratingKey: album.ratingKey,
                    title: album.title,
                    thumb: album.thumb,
                    art: album.art,
                    year: album.year,
                    artist: album.artist,
                    titleSort: album.titleSort,
                    originalTitle: album.originalTitle,
                    editionTitle: album.editionTitle,
                    guid: album.guid,
                    librarySectionID: album.librarySectionID,
                    parentRatingKey: album.parentRatingKey,
                    studio: album.studio,
                    summary: album.summary,
                    rating: album.rating,
                    userRating: album.userRating,
                    key: album.key
                ),
                forKey: .album
            )
        }
        try container.encode(albumRatingKeys, forKey: .albumRatingKeys)
        try container.encodeIfPresent(artworkPath, forKey: .artworkPath)
        try container.encode(isPlayable, forKey: .isPlayable)
        try container.encodeIfPresent(skipReason, forKey: .skipReason)
    }
}

struct QueueState: Codable, Equatable, Sendable {
    let entries: [QueueEntry]
    let currentIndex: Int?
    let elapsedTime: TimeInterval
    let isPlaying: Bool
}

struct QueueInsertRequest: Sendable {
    let mode: QueueInsertMode
    let entries: [QueueEntry]
    let signature: String
    let requestedAt: Date
}

struct QueueInsertResult: Sendable {
    let state: QueueState
    let insertedCount: Int
    let skipped: [QueueInsertSkipReason]
    let duplicateBlocked: Bool
}

protocol QueueStateStoring: Sendable {
    func load() throws -> QueueState?
    func save(_ state: QueueState) throws
    func clear() throws
}

@MainActor
final class QueueManager {
    private var state: QueueState
    private var lastInsertSignature: String?
    private var lastInsertDate: Date?
    private let store: QueueStateStoring
    private let nowProvider: @Sendable () -> Date
    private let persistQueue = DispatchQueue(label: "com.lunara.queue-persist", qos: .utility)
    private var debounceWork: DispatchWorkItem?

    init(
        store: QueueStateStoring = QueueStateStore(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.nowProvider = nowProvider
        self.state = (try? store.load()) ?? QueueState(entries: [], currentIndex: nil, elapsedTime: 0, isPlaying: false)
    }

    func snapshot() -> QueueState {
        state
    }

    @discardableResult
    func setState(_ state: QueueState) async -> QueueState {
        self.state = state
        persist()
        return self.state
    }

    @discardableResult
    func insert(_ request: QueueInsertRequest) async -> QueueInsertResult {
        let now = request.requestedAt
        if shouldBlockDuplicate(signature: request.signature, at: now) {
            return QueueInsertResult(state: state, insertedCount: 0, skipped: [], duplicateBlocked: true)
        }

        var playable: [QueueEntry] = []
        var skipped: [QueueInsertSkipReason] = []
        for entry in request.entries {
            if entry.isPlayable {
                playable.append(entry)
            } else if let reason = entry.skipReason {
                skipped.append(reason)
            } else {
                skipped.append(.unknown)
            }
        }

        guard !playable.isEmpty else {
            return QueueInsertResult(state: state, insertedCount: 0, skipped: skipped, duplicateBlocked: false)
        }

        let current = state.currentIndex
        if state.entries.isEmpty || request.mode == .playNow {
            state = QueueState(entries: playable, currentIndex: 0, elapsedTime: 0, isPlaying: true)
        } else if request.mode == .playNext {
            let insertAt = min((current ?? 0) + 1, state.entries.count)
            var updated = state.entries
            updated.insert(contentsOf: playable, at: insertAt)
            state = QueueState(entries: updated, currentIndex: current, elapsedTime: state.elapsedTime, isPlaying: state.isPlaying)
        } else {
            state = QueueState(
                entries: state.entries + playable,
                currentIndex: current,
                elapsedTime: state.elapsedTime,
                isPlaying: state.isPlaying
            )
        }

        lastInsertSignature = request.signature
        lastInsertDate = now
        persist()
        return QueueInsertResult(state: state, insertedCount: playable.count, skipped: skipped, duplicateBlocked: false)
    }

    @discardableResult
    func clearUpcoming() async -> QueueState {
        guard let currentIndex = state.currentIndex, !state.entries.isEmpty else {
            return state
        }
        guard currentIndex < state.entries.count else {
            return state
        }
        let retainedPrefix = Array(state.entries.prefix(currentIndex + 1))
        state = QueueState(
            entries: retainedPrefix,
            currentIndex: currentIndex,
            elapsedTime: state.elapsedTime,
            isPlaying: state.isPlaying
        )
        persist()
        return state
    }

    @discardableResult
    func removeUpcoming(entryID: UUID) async -> QueueState {
        guard let index = state.entries.firstIndex(where: { $0.id == entryID }) else { return state }
        guard let currentIndex = state.currentIndex, index > currentIndex else { return state }

        var updated = state.entries
        updated.remove(at: index)
        state = QueueState(
            entries: updated,
            currentIndex: currentIndex,
            elapsedTime: state.elapsedTime,
            isPlaying: state.isPlaying
        )
        persist()
        return state
    }

    func entry(at index: Int) -> QueueEntry? {
        guard index >= 0, index < state.entries.count else { return nil }
        return state.entries[index]
    }

    @discardableResult
    func updatePlayback(
        currentIndex: Int?,
        elapsedTime: TimeInterval,
        isPlaying: Bool
    ) async -> QueueState {
        let resolvedIndex: Int?
        if let currentIndex, currentIndex >= 0, currentIndex < state.entries.count {
            resolvedIndex = currentIndex
        } else {
            resolvedIndex = state.currentIndex
        }
        state = QueueState(
            entries: state.entries,
            currentIndex: resolvedIndex,
            elapsedTime: max(0, elapsedTime),
            isPlaying: isPlaying
        )
        persist()
        return state
    }

    private func shouldBlockDuplicate(signature: String, at now: Date) -> Bool {
        guard let lastSignature = lastInsertSignature,
              let lastDate = lastInsertDate,
              lastSignature == signature else {
            return false
        }
        return now.timeIntervalSince(lastDate) < 1
    }

    func persistImmediately() {
        debounceWork?.cancel()
        debounceWork = nil
        let snapshot = state
        if snapshot.entries.isEmpty {
            try? store.clear()
            return
        }
        try? store.save(snapshot)
    }

    private func persist() {
        debounceWork?.cancel()
        let snapshot = state
        if snapshot.entries.isEmpty {
            try? store.clear()
            return
        }
        let store = self.store
        let work = DispatchWorkItem {
            try? store.save(snapshot)
        }
        debounceWork = work
        persistQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
