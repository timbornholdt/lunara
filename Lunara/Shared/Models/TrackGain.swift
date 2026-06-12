import Foundation

/// ReplayGain-style loudness offsets for one track, in dB relative to the
/// -18 LUFS ReplayGain 2 reference (verified against the live server,
/// Lunara-ntt): negative for loud masters, positive for quiet ones.
/// Plex's analysis is album-level — `gain` and `albumGain` are equal on every
/// observed track — but both are kept so per-track analysis would flow through.
struct TrackGain: Equatable, Sendable {
    let gain: Float?
    let albumGain: Float?

    /// nil when the server reported neither attribute.
    var isEmpty: Bool {
        gain == nil && albumGain == nil
    }
}
