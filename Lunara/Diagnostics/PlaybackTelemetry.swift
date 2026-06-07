import Foundation
import Observation

/// Opt-in recorder that appends process-memory + playback-lifecycle samples to a
/// JSONL file the user can export. Off by default and zero-cost when disabled.
///
/// The main-actor surface (toggle, engine emissions, scene phase) is thin; the
/// actual file IO and the periodic sampler run through a thread-safe `TelemetryWriter`
/// so the GCD sampler keeps firing while the app is backgrounded (a main-RunLoop
/// Timer would not — and backgrounded memory is exactly what we want to capture).
@MainActor
@Observable
final class PlaybackTelemetry: PlaybackTelemetryEmitting {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            handleEnabledChange()
        }
    }

    let fileURL: URL
    var previousFileURL: URL { writer.previousFileURL }

    private let writer: TelemetryWriter
    private let defaults: UserDefaults
    private let enabledKey = "playbackTelemetry.isEnabled"

    init(
        probe: MemoryProbing = MemoryProbe(),
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        maxBytes: Int = 5_000_000,
        defaults: UserDefaults = .standard
    ) {
        let url = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.fileURL = url
        self.writer = TelemetryWriter(
            fileURL: url,
            fileManager: fileManager,
            maxBytes: maxBytes,
            probe: probe
        )
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: enabledKey)
        if isEnabled {
            startSession()
        }
    }

    // MARK: - PlaybackTelemetryEmitting

    func record(_ event: PlaybackTelemetryEvent) {
        guard isEnabled else { return }
        writer.updateContext(from: event)
        writer.append(eventName: event.kind.rawValue)
    }

    // MARK: - Recorder-originated events

    func recordScenePhase(active: Bool) {
        guard isEnabled else { return }
        writer.append(eventName: active ? "appForeground" : "appBackground")
    }

    /// Writes one `sample` line from the last-known playback context. Called by the
    /// periodic sampler; exposed for deterministic tests.
    func sampleNow() {
        guard isEnabled else { return }
        writer.append(eventName: "sample")
    }

    // MARK: - Export / lifecycle

    func exportFileURL() -> URL? {
        writer.exportFileURL()
    }

    func clear() {
        writer.clear()
    }

    /// Drains pending writes — used by tests to read deterministically.
    func flush() {
        writer.flush()
    }

    // MARK: - Private

    private func handleEnabledChange() {
        defaults.set(isEnabled, forKey: enabledKey)
        if isEnabled {
            startSession()
        } else {
            writer.stopSampling()
        }
    }

    private func startSession() {
        writer.append(eventName: "sessionStart")
        writer.startSampling()
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documents.appendingPathComponent("playback-telemetry.jsonl", isDirectory: false)
    }
}

/// Thread-safe JSONL writer + last-known-context holder. Safe to call from any
/// thread (the main actor for events, a GCD queue for the periodic sampler).
private final class TelemetryWriter: @unchecked Sendable {
    let fileURL: URL
    let previousFileURL: URL

    private let fileManager: FileManager
    private let maxBytes: Int
    private let probe: MemoryProbing
    private let encoder = JSONEncoder()
    private let ioQueue = DispatchQueue(label: "holdings.chinlock.lunara.telemetry")
    private let lock = NSLock()
    private var context = Context()
    private var sampler: DispatchSourceTimer?

    private struct Context {
        var slots = 0
        var state = "idle"
        var trackID: String?
        var durationSeconds: Double?
        var crossfadeEnabled = false
    }

    init(fileURL: URL, fileManager: FileManager, maxBytes: Int, probe: MemoryProbing) {
        self.fileURL = fileURL
        self.previousFileURL = fileURL.deletingPathExtension()
            .appendingPathExtension("previous." + fileURL.pathExtension)
        self.fileManager = fileManager
        self.maxBytes = maxBytes
        self.probe = probe
    }

    deinit {
        sampler?.cancel()
    }

    /// Starts a 5s GCD sampler (fires in background, unlike a main-RunLoop Timer).
    func startSampling() {
        lock.lock()
        defer { lock.unlock() }
        sampler?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.append(eventName: "sample")
        }
        timer.resume()
        sampler = timer
    }

    func stopSampling() {
        lock.lock()
        defer { lock.unlock() }
        sampler?.cancel()
        sampler = nil
    }

    func updateContext(from event: PlaybackTelemetryEvent) {
        lock.lock()
        defer { lock.unlock() }
        context.slots = event.slots
        context.state = event.state
        context.trackID = event.trackID
        context.durationSeconds = event.durationSeconds
        context.crossfadeEnabled = event.crossfadeEnabled
    }

    func append(eventName: String) {
        let snapshot = currentContext()
        let entry = TelemetryEntry(
            t: Date().ISO8601Format(),
            ev: eventName,
            footMB: megabytes(probe.footprintBytes()),
            availMB: megabytes(probe.availableBytes()),
            slots: snapshot.slots,
            state: snapshot.state,
            cf: snapshot.crossfadeEnabled,
            trackID: snapshot.trackID,
            durS: snapshot.durationSeconds
        )
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A) // newline
        ioQueue.async { [self] in
            write(data)
        }
    }

    func exportFileURL() -> URL? {
        ioQueue.sync {
            let mainHasData = nonEmpty(fileURL)
            let previousHasData = nonEmpty(previousFileURL)
            guard mainHasData || previousHasData else { return nil }
            guard previousHasData else { return mainHasData ? fileURL : nil }

            // Stitch the rotated backup + current file so the export has everything.
            let exportURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("playback-telemetry-export.jsonl", isDirectory: false)
            let previousData = (try? Data(contentsOf: previousFileURL)) ?? Data()
            let mainData = mainHasData ? ((try? Data(contentsOf: fileURL)) ?? Data()) : Data()
            try? (previousData + mainData).write(to: exportURL, options: .atomic)
            return exportURL
        }
    }

    func clear() {
        ioQueue.sync {
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: previousFileURL)
        }
    }

    func flush() {
        ioQueue.sync {}
    }

    // MARK: - Private (ioQueue)

    private func currentContext() -> Context {
        lock.lock()
        defer { lock.unlock() }
        return context
    }

    private func write(_ data: Data) {
        rotateIfNeeded(incomingBytes: data.count)
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics are best-effort; never disrupt playback on a write failure.
        }
    }

    private func rotateIfNeeded(incomingBytes: Int) {
        let size = fileSize(fileURL)
        guard size > 0, size + incomingBytes > maxBytes else { return }
        try? fileManager.removeItem(at: previousFileURL)
        try? fileManager.moveItem(at: fileURL, to: previousFileURL)
    }

    private func nonEmpty(_ url: URL) -> Bool {
        fileSize(url) > 0
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    private func megabytes(_ bytes: UInt64) -> Double {
        (Double(bytes) / 1_048_576 * 10).rounded() / 10
    }
}
