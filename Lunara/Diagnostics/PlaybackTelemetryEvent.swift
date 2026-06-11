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
    /// Free-form detail fields for span/decision records (playStart, fadeDecision,
    /// queueBuild — Lunara-lz4). Omitted entirely for plain lifecycle events.
    var info: [String: String]?

    init(
        t: String, ev: String, footMB: Double, availMB: Double, slots: Int,
        state: String, cf: Bool, trackID: String?, durS: Double?,
        info: [String: String]? = nil
    ) {
        self.t = t
        self.ev = ev
        self.footMB = footMB
        self.availMB = availMB
        self.slots = slots
        self.state = state
        self.cf = cf
        self.trackID = trackID
        self.durS = durS
        self.info = info
    }
}

/// The seam the engine and queue use to emit telemetry. `@MainActor` because
/// both are main-actor isolated and emit from their transitions.
@MainActor
protocol PlaybackTelemetryEmitting: AnyObject {
    var isEnabled: Bool { get }
    func record(_ event: PlaybackTelemetryEvent)
    /// Writes one detail record (timing spans, crossfade decisions) keyed by
    /// `eventName` with free-form `info` fields. No-op when disabled.
    func recordDetail(eventName: String, info: [String: String])
}
