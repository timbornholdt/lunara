import Foundation
import Testing
@testable import Lunara

struct OfflineFileStoreTests {
    @Test func trackRelativePathIsDeterministic() throws {
        let root = makeTempDirectory()
        let store = OfflineFileStore(baseURL: root)

        let a = store.makeTrackRelativePath(trackRatingKey: "1", partKey: "/library/parts/abc/file.flac")
        let b = store.makeTrackRelativePath(trackRatingKey: "1", partKey: "/library/parts/abc/file.flac")

        #expect(a == b)
        #expect(a.hasPrefix("tracks/"))
        #expect(a.hasSuffix(".audio"))
    }

    @Test func trackRelativePathDiffersByPartKey() throws {
        let root = makeTempDirectory()
        let store = OfflineFileStore(baseURL: root)

        let a = store.makeTrackRelativePath(trackRatingKey: "1", partKey: "/library/parts/abc/file.flac")
        let b = store.makeTrackRelativePath(trackRatingKey: "1", partKey: "/library/parts/xyz/file.flac")

        #expect(a != b)
    }

    @Test func saveAndRemoveDataRoundTrips() throws {
        let root = makeTempDirectory()
        let store = OfflineFileStore(baseURL: root)
        let path = store.makeTrackRelativePath(trackRatingKey: "2", partKey: "/library/parts/2/file.mp3")
        let data = Data([0x01, 0x02, 0x03])

        try store.write(data, toRelativePath: path)
        let maybeLoaded = try store.readData(atRelativePath: path)
        let loaded = try #require(maybeLoaded)
        #expect(loaded == data)

        try store.removeFile(atRelativePath: path)
        let afterRemove = try store.readData(atRelativePath: path)
        #expect(afterRemove == nil)
    }

    @Test func removeAllClearsRoot() throws {
        let root = makeTempDirectory()
        let store = OfflineFileStore(baseURL: root)
        let path = store.makeTrackRelativePath(trackRatingKey: "3", partKey: "/library/parts/3/file.mp3")

        try store.write(Data([0x0A]), toRelativePath: path)
        #expect(FileManager.default.fileExists(atPath: store.absoluteURL(forRelativePath: path).path))

        try store.removeAll()

        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineFileStoreTests.\(UUID().uuidString)", isDirectory: true)
    }
}
