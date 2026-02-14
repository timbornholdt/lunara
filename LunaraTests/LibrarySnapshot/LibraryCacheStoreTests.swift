import Foundation
import Testing
@testable import Lunara

struct LibraryCacheStoreTests {
    private func makeTempStore() -> (LibraryCacheStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryCacheStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (LibraryCacheStore(baseURL: url), url)
    }

    @Test func saveAndLoadRoundTrips() {
        let (store, _) = makeTempStore()
        let collections = [
            PlexCollection(ratingKey: "1", title: "Vibes", thumb: nil, art: nil, updatedAt: nil, key: nil)
        ]
        store.save(key: .collections, value: collections)
        let loaded = store.load(key: .collections, as: [PlexCollection].self)
        #expect(loaded == collections)
    }

    @Test func loadMissingKeyReturnsNil() {
        let (store, _) = makeTempStore()
        let result = store.load(key: .artists, as: [PlexArtist].self)
        #expect(result == nil)
    }

    @Test func removeDeletesCachedValue() {
        let (store, _) = makeTempStore()
        store.save(key: .albums, value: ["test"])
        store.remove(key: .albums)
        let result = store.load(key: .albums, as: [String].self)
        #expect(result == nil)
    }

    @Test func clearRemovesAllKeys() {
        let (store, _) = makeTempStore()
        store.save(key: .collections, value: ["a"])
        store.save(key: .artists, value: ["b"])
        store.clear()
        #expect(store.load(key: .collections, as: [String].self) == nil)
        #expect(store.load(key: .artists, as: [String].self) == nil)
    }

    @Test func keySanitizesColonsAndSlashes() {
        let key = LibraryCacheKey.collectionAlbums("foo:bar/baz")
        #expect(key.stringValue == "collectionAlbums_foo_bar_baz")
    }

    @Test func detailKeysProduceDistinctValues() {
        let a = LibraryCacheKey.artistDetail("42")
        let b = LibraryCacheKey.artistAlbums("42")
        #expect(a.stringValue != b.stringValue)
    }

    @Test func overwriteReplacesValue() {
        let (store, _) = makeTempStore()
        store.save(key: .collections, value: ["old"])
        store.save(key: .collections, value: ["new"])
        let result = store.load(key: .collections, as: [String].self)
        #expect(result == ["new"])
    }
}
