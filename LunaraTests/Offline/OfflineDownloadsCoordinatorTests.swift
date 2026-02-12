import Foundation
import Testing
@testable import Lunara

@MainActor
struct OfflineDownloadsCoordinatorTests {
    @Test func queuesWhenOfflineThenResumesWhenWifiReturns() async throws {
        let context = makeContext(
            wifiOn: false,
            trackMap: ["album-1": [makeTrack("track-1", partKey: "/library/parts/1/file.mp3")]],
            downloader: StubDownloader(payloadByTrack: [
                "track-1": OfflineDownloadedPayload(data: Data([0x01, 0x02, 0x03]), expectedBytes: 3, suggestedFileExtension: "mp3")
            ])
        )

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-1",
            displayTitle: "Album One",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-1"],
            source: .explicitAlbum
        )

        let snapshotBefore = await context.coordinator.snapshot()
        #expect(snapshotBefore.pendingCount == 1)
        #expect(context.downloader.callCount == 0)

        context.monitor.setConnected(true)

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.completedFileCount == 1
        }

        #expect(context.downloader.callCount == 1)
        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.albums["album-1"]?.isExplicit == true)
        #expect(manifest.tracks["track-1"]?.state == .completed)

        let path = try #require(manifest.tracks["track-1"]?.relativeFilePath)
        #expect(FileManager.default.fileExists(atPath: context.fileStore.absoluteURL(forRelativePath: path).path))
    }

    @Test func marksTrackFailedWhenExpectedBytesMismatch() async throws {
        let context = makeContext(
            wifiOn: true,
            trackMap: ["album-a": [makeTrack("track-a", partKey: "/library/parts/a/file.mp3")]],
            downloader: StubDownloader(payloadByTrack: [
                "track-a": OfflineDownloadedPayload(data: Data([0x0A, 0x0B, 0x0C]), expectedBytes: 10, suggestedFileExtension: "mp3")
            ])
        )

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-a",
            displayTitle: "Album A",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-a"],
            source: .explicitAlbum
        )

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["track-a"]?.state == .failed
        }

        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.completedFileCount == 0)
        #expect(manifest.tracks["track-a"]?.relativeFilePath == nil)
    }

    @Test func marksTrackFailedWhenPayloadEmpty() async throws {
        let context = makeContext(
            wifiOn: true,
            trackMap: ["album-z": [makeTrack("track-z", partKey: "/library/parts/z/file.mp3")]],
            downloader: StubDownloader(payloadByTrack: [
                "track-z": OfflineDownloadedPayload(data: Data(), expectedBytes: nil, suggestedFileExtension: "mp3")
            ])
        )

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-z",
            displayTitle: "Album Z",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-z"],
            source: .explicitAlbum
        )

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["track-z"]?.state == .failed
        }

        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.completedFileCount == 0)
    }

    @Test func opportunisticCachingRunsOnlyOnWifiAndCapsAtCurrentPlusFive() async throws {
        let tracks = [makeTrack("t0", partKey: "/library/parts/0/file.mp3")]
            + (1...9).map { index in
                makeTrack("t\(index)", partKey: "/library/parts/\(index)/file.mp3")
            }
        let payloads = Dictionary(uniqueKeysWithValues: tracks.map { track in
            (track.ratingKey, OfflineDownloadedPayload(data: Data([0x01]), expectedBytes: 1, suggestedFileExtension: "mp3"))
        })
        let context = makeContext(
            wifiOn: false,
            trackMap: [:],
            downloader: StubDownloader(payloadByTrack: payloads)
        )

        await context.coordinator.enqueueOpportunistic(
            current: tracks[0],
            upcoming: Array(tracks.dropFirst()),
            limit: 5
        )
        #expect(context.downloader.callCount == 0)

        context.monitor.setConnected(true)
        await context.coordinator.enqueueOpportunistic(
            current: tracks[0],
            upcoming: Array(tracks.dropFirst()),
            limit: 5
        )

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.completedFileCount == 6
        }

        #expect(context.downloader.callCount == 6)
        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.tracks.values.filter { $0.isOpportunistic }.count == 6)
    }

    @Test func publishesInProgressBytesDuringDownload() async throws {
        let track = makeTrack("progress-track", partKey: "/library/parts/p/file.mp3")
        let downloader = StubDownloader(
            payloadByTrack: [
                "progress-track": OfflineDownloadedPayload(data: Data(repeating: 0x01, count: 10), expectedBytes: 10, suggestedFileExtension: "mp3")
            ],
            progressBytes: 5,
            delayAfterProgressNanoseconds: 200_000_000
        )
        let context = makeContext(
            wifiOn: true,
            trackMap: ["album-p": [track]],
            downloader: downloader
        )

        let enqueueTask = Task {
            try await context.coordinator.enqueueAlbumDownload(
                albumIdentity: "album-p",
                displayTitle: "Album P",
                artistName: nil,
                artworkPath: nil,
                albumRatingKeys: ["album-p"],
                source: .explicitAlbum
            )
        }

        try await waitUntil {
            let snapshot = await context.coordinator.snapshot()
            guard let first = snapshot.inProgressTracks.first(where: { $0.trackRatingKey == "progress-track" }) else {
                return false
            }
            return first.bytesReceived == 5 && first.expectedBytes == 10
        }

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["progress-track"]?.state == .completed
        }
        _ = try await enqueueTask.value
    }

    @Test func removeExplicitAlbumDownloadDeletesAlbumAndTracks() async throws {
        let context = makeContext(
            wifiOn: true,
            trackMap: ["album-remove": [makeTrack("track-remove", partKey: "/library/parts/r/file.mp3")]],
            downloader: StubDownloader(payloadByTrack: [
                "track-remove": OfflineDownloadedPayload(data: Data([0x01, 0x02]), expectedBytes: 2, suggestedFileExtension: "mp3")
            ])
        )

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-remove",
            displayTitle: "Album Remove",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-remove"],
            source: .explicitAlbum
        )
        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["track-remove"]?.state == .completed
        }
        let completedManifest = try context.manifestStore.load()
        let manifestBefore = try #require(completedManifest)
        let pathBefore = try #require(manifestBefore.tracks["track-remove"]?.relativeFilePath)
        let fileBefore = context.fileStore.absoluteURL(forRelativePath: pathBefore)
        #expect(FileManager.default.fileExists(atPath: fileBefore.path))

        try await context.coordinator.removeAlbumDownload(albumIdentity: "album-remove")

        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.albums["album-remove"] == nil)
        #expect(manifest.tracks["track-remove"] == nil)
        #expect(FileManager.default.fileExists(atPath: fileBefore.path) == false)
    }

    @Test func removingCollectionPreservesExplicitAlbumDownload() async throws {
        let context = makeContext(
            wifiOn: true,
            trackMap: ["album-preserve": [makeTrack("track-preserve", partKey: "/library/parts/preserve/file.mp3")]],
            downloader: StubDownloader(payloadByTrack: [
                "track-preserve": OfflineDownloadedPayload(data: Data([0x05, 0x06]), expectedBytes: 2, suggestedFileExtension: "mp3")
            ])
        )

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-preserve",
            displayTitle: "Album Preserve",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-preserve"],
            source: .explicitAlbum
        )
        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-preserve",
            displayTitle: "Album Preserve",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-preserve"],
            source: .collection("collection-1")
        )
        try await context.coordinator.upsertCollectionRecord(
            collectionKey: "collection-1",
            title: "Collection 1",
            albumIdentities: ["album-preserve"]
        )

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["track-preserve"]?.state == .completed
        }

        try await context.coordinator.removeCollectionDownload(collectionKey: "collection-1")

        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.collections["collection-1"] == nil)
        #expect(manifest.albums["album-preserve"]?.isExplicit == true)
        #expect(manifest.albums["album-preserve"]?.collectionKeys.isEmpty == true)
        #expect(manifest.tracks["track-preserve"]?.state == .completed)
    }

    @Test func evictsNonExplicitLeastRecentlyPlayedTracksFirst() async throws {
        let context = makeContext(
            wifiOn: true,
            trackMap: [
                "album-ne-1": [makeTrack("ne-1", partKey: "/library/parts/ne-1/file.mp3")],
                "album-ne-2": [makeTrack("ne-2", partKey: "/library/parts/ne-2/file.mp3")],
                "album-explicit": [makeTrack("explicit-1", partKey: "/library/parts/explicit-1/file.mp3")]
            ],
            downloader: StubDownloader(payloadByTrack: [
                "ne-1": OfflineDownloadedPayload(data: Data([0x01, 0x02, 0x03]), expectedBytes: 3, suggestedFileExtension: "mp3"),
                "ne-2": OfflineDownloadedPayload(data: Data([0x04, 0x05, 0x06]), expectedBytes: 3, suggestedFileExtension: "mp3"),
                "explicit-1": OfflineDownloadedPayload(data: Data([0x07, 0x08, 0x09, 0x0A]), expectedBytes: 4, suggestedFileExtension: "mp3")
            ]),
            maxStorageBytes: 7
        )

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-ne-1",
            displayTitle: "Non Explicit 1",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-ne-1"],
            source: .collection("collection-1")
        )
        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-ne-2",
            displayTitle: "Non Explicit 2",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-ne-2"],
            source: .collection("collection-1")
        )

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["ne-2"]?.state == .completed
        }

        let playbackIndex = OfflinePlaybackIndex(
            manifestStore: context.manifestStore,
            fileStore: context.fileStore
        )
        playbackIndex.markPlayed(trackKey: "ne-1", at: Date(timeIntervalSince1970: 200))
        playbackIndex.markPlayed(trackKey: "ne-2", at: Date(timeIntervalSince1970: 100))

        try await context.coordinator.enqueueAlbumDownload(
            albumIdentity: "album-explicit",
            displayTitle: "Explicit",
            artistName: nil,
            artworkPath: nil,
            albumRatingKeys: ["album-explicit"],
            source: .explicitAlbum
        )

        try await waitUntil {
            let manifest = try context.manifestStore.load()
            return manifest?.tracks["explicit-1"]?.state == .completed
        }

        let loadedManifest = try context.manifestStore.load()
        let manifest = try #require(loadedManifest)
        #expect(manifest.totalBytes == 7)
        #expect(manifest.tracks["explicit-1"]?.state == .completed)
        #expect(manifest.tracks["ne-1"]?.state == .completed)
        #expect(manifest.tracks["ne-2"] == nil)
    }

    @Test func throwsWhenOverCapAndOnlyExplicitDownloadsRemain() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineDownloadsCoordinatorTests.\(UUID().uuidString)", isDirectory: true)
        let manifestStore = OfflineManifestStore(baseURL: base.appendingPathComponent("manifest", isDirectory: true))
        let fileStore = OfflineFileStore(baseURL: base.appendingPathComponent("files", isDirectory: true))
        let relativePath = fileStore.makeTrackRelativePath(trackRatingKey: "explicit-a", partKey: "/parts/a")
        try fileStore.write(Data(repeating: 0x01, count: 10), toRelativePath: relativePath)
        try manifestStore.save(
            OfflineManifest(
                tracks: [
                    "explicit-a": OfflineTrackRecord(
                        trackRatingKey: "explicit-a",
                        trackTitle: nil,
                        artistName: nil,
                        partKey: "/parts/a",
                        relativeFilePath: relativePath,
                        expectedBytes: 10,
                        actualBytes: 10,
                        state: .completed,
                        isOpportunistic: false,
                        lastPlayedAt: Date(timeIntervalSince1970: 1),
                        completedAt: Date(timeIntervalSince1970: 1)
                    )
                ],
                albums: [
                    "album-explicit-a": OfflineAlbumRecord(
                        albumIdentity: "album-explicit-a",
                        displayTitle: "Explicit A",
                        artistName: nil,
                        artworkPath: nil,
                        trackKeys: ["explicit-a"],
                        isExplicit: true,
                        collectionKeys: []
                    )
                ]
            )
        )
        let monitor = StubWiFiMonitor(isOnWiFi: true)
        let coordinator = OfflineDownloadsCoordinator.make(
            manifestStore: manifestStore,
            fileStore: fileStore,
            trackFetcher: StubTrackFetcher(trackMap: [
                "new-album": [makeTrack("new-track", partKey: "/parts/new")]
            ]),
            downloader: StubDownloader(payloadByTrack: [
                "new-track": OfflineDownloadedPayload(data: Data([0x01]), expectedBytes: 1, suggestedFileExtension: "mp3")
            ]),
            wifiMonitor: monitor,
            nowProvider: { Date(timeIntervalSince1970: 1000) },
            maxStorageBytes: 5
        )

        do {
            try await coordinator.enqueueAlbumDownload(
                albumIdentity: "new-album",
                displayTitle: "New Album",
                artistName: nil,
                artworkPath: nil,
                albumRatingKeys: ["new-album"],
                source: .explicitAlbum
            )
            Issue.record("Expected insufficient storage error")
        } catch let error as OfflineDownloadError {
            #expect(error == .insufficientStorageNonEvictable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeTrack(_ key: String, partKey: String) -> PlexTrack {
        PlexTrack(
            ratingKey: key,
            title: key,
            index: 1,
            parentIndex: nil,
            parentRatingKey: "parent-\(key)",
            duration: 1000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: partKey)])]
        )
    }

    private func makeContext(
        wifiOn: Bool,
        trackMap: [String: [PlexTrack]],
        downloader: StubDownloader,
        maxStorageBytes: Int64 = 120 * 1024 * 1024 * 1024
    ) -> TestContext {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineDownloadsCoordinatorTests.\(UUID().uuidString)", isDirectory: true)
        let manifestStore = OfflineManifestStore(baseURL: base.appendingPathComponent("manifest", isDirectory: true))
        let fileStore = OfflineFileStore(baseURL: base.appendingPathComponent("files", isDirectory: true))
        let monitor = StubWiFiMonitor(isOnWiFi: wifiOn)
        let fetcher = StubTrackFetcher(trackMap: trackMap)
        let coordinator = OfflineDownloadsCoordinator.make(
            manifestStore: manifestStore,
            fileStore: fileStore,
            trackFetcher: fetcher,
            downloader: downloader,
            wifiMonitor: monitor,
            nowProvider: { Date(timeIntervalSince1970: 999) },
            maxStorageBytes: maxStorageBytes
        )

        return TestContext(
            coordinator: coordinator,
            manifestStore: manifestStore,
            fileStore: fileStore,
            downloader: downloader,
            monitor: monitor
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping () async throws -> Bool
    ) async throws {
        let deadline = Date().timeIntervalSince1970 + (Double(timeoutNanoseconds) / 1_000_000_000)
        while Date().timeIntervalSince1970 < deadline {
            if try await condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        Issue.record("Timed out waiting for condition")
    }
}

private struct TestContext {
    let coordinator: OfflineDownloadsCoordinator
    let manifestStore: OfflineManifestStore
    let fileStore: OfflineFileStore
    let downloader: StubDownloader
    let monitor: StubWiFiMonitor
}

private final class StubTrackFetcher: OfflineTrackFetching {
    private let trackMap: [String: [PlexTrack]]

    init(trackMap: [String: [PlexTrack]]) {
        self.trackMap = trackMap
    }

    func fetchMergedTracks(albumRatingKeys: [String]) async throws -> [PlexTrack] {
        var merged: [PlexTrack] = []
        for key in albumRatingKeys {
            merged.append(contentsOf: trackMap[key] ?? [])
        }
        return merged
    }
}

private final class StubDownloader: OfflineTrackDownloading {
    private let payloadByTrack: [String: OfflineDownloadedPayload]
    private let progressBytes: Int64?
    private let delayAfterProgressNanoseconds: UInt64
    private(set) var callCount = 0

    init(
        payloadByTrack: [String: OfflineDownloadedPayload],
        progressBytes: Int64? = nil,
        delayAfterProgressNanoseconds: UInt64 = 0
    ) {
        self.payloadByTrack = payloadByTrack
        self.progressBytes = progressBytes
        self.delayAfterProgressNanoseconds = delayAfterProgressNanoseconds
    }

    func downloadTrack(
        trackRatingKey: String,
        partKey: String,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> OfflineDownloadedPayload {
        callCount += 1
        guard let payload = payloadByTrack[trackRatingKey] else {
            throw TestError.missingPayload(trackRatingKey)
        }
        if let progressBytes {
            progress(progressBytes, payload.expectedBytes ?? payload.actualBytes)
            if delayAfterProgressNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayAfterProgressNanoseconds)
            }
        }
        return payload
    }
}

private final class StubWiFiMonitor: WiFiReachabilityMonitoring {
    private var changeHandler: (@Sendable (Bool) -> Void)?

    var isOnWiFi: Bool

    init(isOnWiFi: Bool) {
        self.isOnWiFi = isOnWiFi
    }

    func setOnWiFiChangeHandler(_ handler: (@Sendable (Bool) -> Void)?) {
        changeHandler = handler
    }

    func setConnected(_ connected: Bool) {
        isOnWiFi = connected
        changeHandler?(connected)
    }
}

private enum TestError: Error {
    case missingPayload(String)
}
