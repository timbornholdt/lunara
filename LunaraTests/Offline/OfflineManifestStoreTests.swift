import Foundation
import Testing
@testable import Lunara

struct OfflineManifestStoreTests {
    @Test func loadReturnsNilWhenManifestMissing() throws {
        let root = makeTempDirectory()
        let store = OfflineManifestStore(baseURL: root)

        let loaded = try store.load()

        #expect(loaded == nil)
    }

    @Test func saveAndLoadRoundTripsManifest() throws {
        let root = makeTempDirectory()
        let store = OfflineManifestStore(baseURL: root)
        let manifest = OfflineManifest(
            tracks: [
                "track-1": OfflineTrackRecord(
                    trackRatingKey: "track-1",
                    trackTitle: nil,
                    artistName: nil,
                    partKey: "/library/parts/1/file.flac",
                    relativeFilePath: "tracks/a.audio",
                    expectedBytes: 123,
                    actualBytes: 123,
                    state: .completed,
                    isOpportunistic: false,
                    lastPlayedAt: Date(timeIntervalSince1970: 100),
                    completedAt: Date(timeIntervalSince1970: 200)
                )
            ],
            albums: [
                "album-a": OfflineAlbumRecord(
                    albumIdentity: "album-a",
                    displayTitle: "Album A",
                    artistName: nil,
                    artworkPath: nil,
                    trackKeys: ["track-1"],
                    isExplicit: true,
                    collectionKeys: []
                )
            ],
            collections: [
                "collection-a": OfflineCollectionRecord(
                    collectionKey: "collection-a",
                    title: "Collection A",
                    albumIdentities: ["album-a"],
                    lastReconciledAt: Date(timeIntervalSince1970: 300)
                )
            ]
        )

        try store.save(manifest)
        let maybeLoaded = try store.load()
        let loaded = try #require(maybeLoaded)

        #expect(loaded.schemaVersion == OfflineManifest.currentSchemaVersion)
        #expect(loaded.tracks["track-1"]?.state == .completed)
        #expect(loaded.albums["album-a"]?.isExplicit == true)
        #expect(loaded.collections["collection-a"]?.albumIdentities == ["album-a"])
        #expect(loaded.completedFileCount == 1)
        #expect(loaded.totalBytes == 123)
    }

    @Test func loadReturnsNilForUnsupportedSchemaVersion() throws {
        let root = makeTempDirectory()
        let store = OfflineManifestStore(baseURL: root)
        let unsupported = UnsupportedManifest(schemaVersion: OfflineManifest.currentSchemaVersion + 1)
        let data = try JSONEncoder().encode(unsupported)
        let manifestURL = root.appendingPathComponent("offline-manifest.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: manifestURL, options: .atomic)

        let loaded = try store.load()

        #expect(loaded == nil)
    }

    private func makeTempDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineManifestStoreTests.\(UUID().uuidString)", isDirectory: true)
        return root
    }
}

private struct UnsupportedManifest: Codable {
    let schemaVersion: Int
}
