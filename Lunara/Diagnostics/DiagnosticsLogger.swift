import Foundation

protocol DiagnosticsLogging {
    func log(_ event: DiagnosticsEvent)
    func startPlaybackSession()
    func endPlaybackSession()
}

final class DiagnosticsLogger: DiagnosticsLogging {
    static let shared = DiagnosticsLogger()

    let fileURL: URL
    let sessionId: UUID

    private var playbackSessionId: UUID?
    private let queue = DispatchQueue(label: "com.lunara.diagnostics", qos: .utility)
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lunara", isDirectory: true)
            self.fileURL = base.appendingPathComponent("diagnostics.jsonl")
        }
        self.sessionId = UUID()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        self.encoder = encoder
    }

    func log(_ event: DiagnosticsEvent) {
        let entry = DiagnosticsEntry(
            timestamp: Date(),
            sessionId: sessionId,
            playbackSessionId: playbackSessionId,
            event: event.name,
            data: event.data
        )
        queue.async { [weak self] in
            self?.writeEntry(entry)
        }
    }

    func startPlaybackSession() {
        playbackSessionId = UUID()
    }

    func endPlaybackSession() {
        playbackSessionId = nil
    }

    private func writeEntry(_ entry: DiagnosticsEntry) {
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")
        let dir = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? fileHandle.close() }
        fileHandle.seekToEndOfFile()
        if let lineData = line.data(using: .utf8) {
            fileHandle.write(lineData)
        }
    }
}

private struct DiagnosticsEntry: Encodable {
    let timestamp: Date
    let sessionId: UUID
    let playbackSessionId: UUID?
    let event: String
    let data: [String: String]
}
