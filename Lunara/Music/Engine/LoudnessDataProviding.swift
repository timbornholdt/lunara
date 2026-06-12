import Foundation

protocol LoudnessDataProviding: Sendable {
    func fetchLoudnessLevels(trackID: String) async throws -> [Float]?
    /// Loudness-leveling offsets for the queue's engine handoff (Lunara-dtv).
    func fetchTrackGain(trackID: String) async throws -> TrackGain?
}

extension LoudnessDataProviding {
    func fetchTrackGain(trackID: String) async throws -> TrackGain? { nil }
}
