import Foundation

protocol LoudnessDataProviding: Sendable {
    func fetchLoudnessLevels(trackID: String) async throws -> [Float]?
}
