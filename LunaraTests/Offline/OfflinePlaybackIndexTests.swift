import Foundation
import Testing
@testable import Lunara

struct OfflinePlaybackIndexTests {
    @Test func fileURLReturnsPathForCompletedTrackOnly() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflinePlaybackIndexTests.\(UUID().uuidString)", isDirectory: true)
        let manifestStore = OfflineManifestStore(baseURL: base.appendingPathComponent("manifest", isDirectory: true))
        let fileStore = OfflineFileStore(baseURL: base.appendingPathComponent("files", isDirectory: true))
        let relativePath = "tracks/track.audio"
        try fileStore.write(Data([0x01, 0x02]), toRelativePath: relativePath)
        let manifest = OfflineManifest(
            tracks: [
                "done": OfflineTrackRecord(
                    trackRatingKey: "done",
                    trackTitle: nil,
                    artistName: nil,
                    partKey: "/library/parts/done/file.mp3",
                    relativeFilePath: relativePath,
                    expectedBytes: 2,
                    actualBytes: 2,
                    state: .completed,
                    isOpportunistic: false,
                    lastPlayedAt: nil,
                    completedAt: Date(timeIntervalSince1970: 100)
                ),
                "pending": OfflineTrackRecord(
                    trackRatingKey: "pending",
                    trackTitle: nil,
                    artistName: nil,
                    partKey: "/library/parts/pending/file.mp3",
                    relativeFilePath: nil,
                    expectedBytes: nil,
                    actualBytes: nil,
                    state: .pending,
                    isOpportunistic: false,
                    lastPlayedAt: nil,
                    completedAt: nil
                )
            ]
        )
        try manifestStore.save(manifest)
        let index = OfflinePlaybackIndex(manifestStore: manifestStore, fileStore: fileStore)

        #expect(index.fileURL(for: "done") == fileStore.absoluteURL(forRelativePath: relativePath))
        #expect(index.fileURL(for: "pending") == nil)
    }

    @Test func markPlayedUpdatesLastPlayedTimestamp() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflinePlaybackIndexTests.\(UUID().uuidString)", isDirectory: true)
        let manifestStore = OfflineManifestStore(baseURL: base.appendingPathComponent("manifest", isDirectory: true))
        let fileStore = OfflineFileStore(baseURL: base.appendingPathComponent("files", isDirectory: true))
        let manifest = OfflineManifest(
            tracks: [
                "done": OfflineTrackRecord(
                    trackRatingKey: "done",
                    trackTitle: nil,
                    artistName: nil,
                    partKey: "/library/parts/done/file.mp3",
                    relativeFilePath: "tracks/done.audio",
                    expectedBytes: 2,
                    actualBytes: 2,
                    state: .completed,
                    isOpportunistic: false,
                    lastPlayedAt: nil,
                    completedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        try manifestStore.save(manifest)
        let index = OfflinePlaybackIndex(manifestStore: manifestStore, fileStore: fileStore)

        let playedAt = Date(timeIntervalSince1970: 999)
        index.markPlayed(trackKey: "done", at: playedAt)

        let loadedManifest = try manifestStore.load()
        let saved = try #require(loadedManifest)
        #expect(saved.tracks["done"]?.lastPlayedAt == playedAt)
    }
}
