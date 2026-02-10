import Foundation
import Testing
@testable import Lunara

struct LibrarySnapshotStoreTests {
    @Test func savesAndLoadsSnapshot() throws {
        let tempURL = try makeTempDirectory()
        let defaults = UserDefaults(suiteName: "tests.snapshot.store")!
        defaults.removePersistentDomain(forName: "tests.snapshot.store")
        let store = LibrarySnapshotStore(baseURL: tempURL, defaults: defaults)
        let snapshot = LibrarySnapshot(
            albums: [
                LibrarySnapshot.Album(
                    ratingKey: "1",
                    title: "Album",
                    thumb: "/thumb/1",
                    art: "/art/1",
                    year: 2024,
                    artist: "Artist"
                )
            ],
            collections: [
                LibrarySnapshot.Collection(
                    ratingKey: "c1",
                    title: "Collection",
                    thumb: "/thumb/c1",
                    art: "/art/c1"
                )
            ]
        )

        try store.save(snapshot)
        let loaded = try store.load()

        #expect(loaded?.albums.count == 1)
        #expect(loaded?.collections.count == 1)
        #expect(loaded?.albums.first?.title == "Album")
    }

    @Test func missingSnapshotReturnsNil() throws {
        let tempURL = try makeTempDirectory()
        let defaults = UserDefaults(suiteName: "tests.snapshot.store.missing")!
        defaults.removePersistentDomain(forName: "tests.snapshot.store.missing")
        let store = LibrarySnapshotStore(baseURL: tempURL, defaults: defaults)

        let loaded = try store.load()

        #expect(loaded == nil)
    }

    @Test func loadsFromDefaultsWhenDiskMissing() throws {
        let tempURL = try makeTempDirectory()
        let defaults = UserDefaults(suiteName: "tests.snapshot.store.fallback")!
        defaults.removePersistentDomain(forName: "tests.snapshot.store.fallback")
        let store = LibrarySnapshotStore(baseURL: tempURL, defaults: defaults)
        let snapshot = LibrarySnapshot(
            albums: [
                .init(
                    ratingKey: "fallback",
                    title: "Fallback Album",
                    thumb: nil,
                    art: nil,
                    year: nil,
                    artist: nil
                )
            ],
            collections: []
        )

        let data = try JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: "library.snapshot.data")

        let loaded = try store.load()

        #expect(loaded?.albums.first?.ratingKey == "fallback")
    }
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
