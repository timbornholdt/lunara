import Foundation
import Testing
@testable import Lunara

struct DiagnosticsLoggerTests {
    @Test func writesValidJSONLToFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("diagnostics.jsonl")
        let logger = DiagnosticsLogger(fileURL: fileURL)

        logger.log(.appLaunch)
        logger.log(.playbackPlay(trackCount: 5, startIndex: 2))

        try await Task.sleep(nanoseconds: 100_000_000)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 2)

        for line in lines {
            let data = Data(line.utf8)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            #expect(json["timestamp"] != nil)
            #expect(json["sessionId"] != nil)
            #expect(json["event"] != nil)
        }

        let firstJSON = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        #expect(firstJSON["event"] as? String == "app.launch")

        let secondJSON = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as! [String: Any]
        #expect(secondJSON["event"] as? String == "playback.play")
        let eventData = secondJSON["data"] as? [String: String]
        #expect(eventData?["trackCount"] == "5")
        #expect(eventData?["startIndex"] == "2")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func sessionIdConsistentAcrossEvents() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("diagnostics.jsonl")
        let logger = DiagnosticsLogger(fileURL: fileURL)

        logger.log(.appLaunch)
        logger.log(.playbackSkipNext)

        try await Task.sleep(nanoseconds: 100_000_000)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        let firstJSON = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        let secondJSON = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as! [String: Any]
        #expect(firstJSON["sessionId"] as? String == secondJSON["sessionId"] as? String)
        #expect(firstJSON["sessionId"] as? String == logger.sessionId.uuidString)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func playbackSessionIdLifecycle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("diagnostics.jsonl")
        let logger = DiagnosticsLogger(fileURL: fileURL)

        logger.log(.appLaunch)
        logger.startPlaybackSession()
        logger.log(.playbackPlay(trackCount: 3, startIndex: 0))
        logger.endPlaybackSession()
        logger.log(.navigationTabChange(tab: "library"))

        try await Task.sleep(nanoseconds: 100_000_000)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 3)

        let launchJSON = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        #expect(launchJSON["playbackSessionId"] is NSNull || launchJSON["playbackSessionId"] == nil)

        let playJSON = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as! [String: Any]
        #expect(playJSON["playbackSessionId"] is String)

        let navJSON = try JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as! [String: Any]
        #expect(navJSON["playbackSessionId"] is NSNull || navJSON["playbackSessionId"] == nil)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func eventDataSerializationRoundTrip() async throws {
        let events: [DiagnosticsEvent] = [
            .appLaunch,
            .playbackPlay(trackCount: 10, startIndex: 3),
            .playbackAudioStarted(trackKey: "track-42"),
            .playbackSkipNext,
            .playbackSkipPrevious,
            .playbackStateChange(trackKey: "track-1", isPlaying: true),
            .playbackUISync(trackKey: "track-1"),
            .navigationTabChange(tab: "collections"),
            .navigationScreenPush(screenType: "album", key: "abc123"),
        ]

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("diagnostics.jsonl")
        let logger = DiagnosticsLogger(fileURL: fileURL)

        for event in events {
            logger.log(event)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == events.count)

        for (index, line) in lines.enumerated() {
            let data = Data(line.utf8)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            #expect(json["event"] as? String == events[index].name)
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
