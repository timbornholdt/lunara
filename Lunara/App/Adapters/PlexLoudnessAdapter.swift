import Foundation

final class PlexLoudnessAdapter: LoudnessDataProviding {
    private let library: LibraryRepoProtocol

    init(library: LibraryRepoProtocol) {
        self.library = library
    }

    func fetchLoudnessLevels(trackID: String) async throws -> [Float]? {
        try await library.fetchLoudnessLevels(trackID: trackID)
    }
}
