import Foundation

/// A playback transition reported by the engine. The engine supplies the
/// authoritative slot count and playback context; the recorder stamps the
/// timestamp and memory figures.
struct PlaybackTelemetryEvent {
    enum Kind: String {
        case play
        case pause
        case resume
        case prepareNext
        case crossfadeBegin
        case crossfadeComplete
        case skip
        case seek
        case stop
        case error
    }

    let kind: Kind
    /// Number of player slots currently holding a loaded file (0, 1, or 2).
    let slots: Int
    /// Engine playback state description (e.g. "playing", "idle").
    let state: String
    let trackID: String?
    let durationSeconds: Double?
    let crossfadeEnabled: Bool
}

/// One serialized line in the JSONL telemetry log.
struct TelemetryEntry: Codable, Equatable {
    let t: String          // ISO8601 timestamp
    let ev: String         // event name
    let footMB: Double     // resident footprint (MB)
    let availMB: Double    // available memory before jetsam (MB), 0 on simulator
    let slots: Int
    let state: String
    let cf: Bool            // crossfade enabled
    let trackID: String?
    let durS: Double?
}

/// The seam the engine uses to emit telemetry. `@MainActor` because the engine
/// is main-actor isolated and emits from its transitions.
@MainActor
protocol PlaybackTelemetryEmitting: AnyObject {
    var isEnabled: Bool { get }
    func record(_ event: PlaybackTelemetryEvent)
}
