import Foundation

final class PlexLoudnessAdapter: LoudnessDataProviding {
    private let library: LibraryRepoProtocol

    init(library: LibraryRepoProtocol) {
        self.library = library
    }

    func fetchLoudnessLevels(trackID: String) async throws -> [Float]? {
        try await library.fetchLoudnessLevels(trackID: trackID)
    }

    func fetchTrackGain(trackID: String) async throws -> TrackGain? {
        try await library.fetchTrackGain(trackID: trackID)
    }
}
