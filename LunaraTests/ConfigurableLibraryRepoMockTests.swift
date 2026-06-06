import Foundation
import Testing
@testable import Lunara

@MainActor
struct ConfigurableLibraryRepoMockTests {
    @Test
    func returnsConfiguredTrackAndAlbum_andEmptyDefaults() async throws {
        let repo = ConfigurableLibraryRepoMock()
        let track = Track(
            plexID: "t1",
            albumID: "a1",
            title: "Song",
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/t1",
            thumbURL: nil
        )
        let album = Album(
            plexID: "a1",
            title: "Record",
            artistName: "Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 1,
            duration: 180
        )
        repo.tracksByID["t1"] = track
        repo.albumsByID["a1"] = album

        #expect(try await repo.track(id: "t1")?.title == "Song")
        #expect(try await repo.album(id: "a1")?.title == "Record")
        #expect(try await repo.track(id: "missing") == nil)
        #expect(try await repo.artists().isEmpty)
        #expect(try await repo.playlists().isEmpty)
    }
}
