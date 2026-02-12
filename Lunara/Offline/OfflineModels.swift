import Foundation

enum OfflineTrackState: String, Codable, Equatable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
}

struct OfflineTrackRecord: Codable, Equatable, Sendable {
    let trackRatingKey: String
    let trackTitle: String?
    let artistName: String?
    let partKey: String?
    let relativeFilePath: String?
    let expectedBytes: Int64?
    let actualBytes: Int64?
    var state: OfflineTrackState
    var isOpportunistic: Bool
    var lastPlayedAt: Date?
    var completedAt: Date?

    var isCompleted: Bool {
        state == .completed
    }
}

struct OfflineAlbumRecord: Codable, Equatable, Sendable {
    let albumIdentity: String
    var displayTitle: String
    var artistName: String?
    var artworkPath: String?
    var sourceAlbumRatingKeys: [String]
    var trackKeys: [String]
    var isExplicit: Bool
    var collectionKeys: [String]

    enum CodingKeys: String, CodingKey {
        case albumIdentity
        case displayTitle
        case artistName
        case artworkPath
        case sourceAlbumRatingKeys
        case trackKeys
        case isExplicit
        case collectionKeys
    }

    init(
        albumIdentity: String,
        displayTitle: String,
        artistName: String?,
        artworkPath: String?,
        sourceAlbumRatingKeys: [String] = [],
        trackKeys: [String],
        isExplicit: Bool,
        collectionKeys: [String]
    ) {
        self.albumIdentity = albumIdentity
        self.displayTitle = displayTitle
        self.artistName = artistName
        self.artworkPath = artworkPath
        self.sourceAlbumRatingKeys = sourceAlbumRatingKeys
        self.trackKeys = trackKeys
        self.isExplicit = isExplicit
        self.collectionKeys = collectionKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        albumIdentity = try container.decode(String.self, forKey: .albumIdentity)
        displayTitle = try container.decode(String.self, forKey: .displayTitle)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        artworkPath = try container.decodeIfPresent(String.self, forKey: .artworkPath)
        sourceAlbumRatingKeys = try container.decodeIfPresent([String].self, forKey: .sourceAlbumRatingKeys) ?? []
        trackKeys = try container.decodeIfPresent([String].self, forKey: .trackKeys) ?? []
        isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
        collectionKeys = try container.decodeIfPresent([String].self, forKey: .collectionKeys) ?? []
    }
}

struct OfflineCollectionRecord: Codable, Equatable, Sendable {
    let collectionKey: String
    var title: String
    var albumIdentities: [String]
    var lastReconciledAt: Date?
}

struct OfflineManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var tracks: [String: OfflineTrackRecord]
    var albums: [String: OfflineAlbumRecord]
    var collections: [String: OfflineCollectionRecord]

    init(
        schemaVersion: Int = OfflineManifest.currentSchemaVersion,
        tracks: [String: OfflineTrackRecord] = [:],
        albums: [String: OfflineAlbumRecord] = [:],
        collections: [String: OfflineCollectionRecord] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.tracks = tracks
        self.albums = albums
        self.collections = collections
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tracks
        case albums
        case collections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        tracks = try container.decodeIfPresent([String: OfflineTrackRecord].self, forKey: .tracks) ?? [:]
        albums = try container.decodeIfPresent([String: OfflineAlbumRecord].self, forKey: .albums) ?? [:]
        collections = try container.decodeIfPresent([String: OfflineCollectionRecord].self, forKey: .collections) ?? [:]
    }

    var completedFileCount: Int {
        tracks.values.filter { $0.isCompleted && $0.relativeFilePath != nil }.count
    }

    var totalBytes: Int64 {
        tracks.values
            .filter { $0.isCompleted }
            .reduce(0) { partial, track in
                partial + (track.actualBytes ?? 0)
            }
    }

    var containsLegacyAudioFiles: Bool {
        tracks.values.contains { record in
            guard let relativePath = record.relativeFilePath else { return false }
            return relativePath.lowercased().hasSuffix(".audio")
        }
    }
}

protocol OfflineManifestStoring {
    func load() throws -> OfflineManifest?
    func save(_ manifest: OfflineManifest) throws
    func clear() throws
}
