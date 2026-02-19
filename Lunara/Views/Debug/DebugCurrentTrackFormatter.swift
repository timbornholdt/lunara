import Foundation

enum DebugCurrentTrackFormatter {
    static func label(for trackID: String?, tracksByID: [String: Track]) -> String {
        guard let trackID else {
            return "none"
        }

        guard let track = tracksByID[trackID] else {
            return trackID
        }

        return "\(track.artistName) - \(track.title) (\(trackID))"
    }
}
