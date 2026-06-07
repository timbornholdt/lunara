import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaybackTelemetryTests {
    @Test
    func disabled_recordsNothing() {
        let (telemetry, url) = makeTelemetry()

        telemetry.record(prepareNextEvent())
        telemetry.flush()

        #expect(readEntries(url).isEmpty)
        #expect(telemetry.exportFileURL() == nil)
    }

    @Test
    func enabling_writesSessionStartAndExposesExportURL() {
        let (telemetry, url) = makeTelemetry()

        telemetry.isEnabled = true
        telemetry.flush()

        #expect(readEntries(url).contains { $0.ev == "sessionStart" })
        #expect(telemetry.exportFileURL() != nil)
    }

    @Test
    func record_stampsMemorySlotsAndContext() throws {
        let (telemetry, url) = makeTelemetry(footprintBytes: 104_857_600, availableBytes: 0)
        telemetry.isEnabled = true

        telemetry.record(
            PlaybackTelemetryEvent(
                kind: .prepareNext,
                slots: 2,
                state: "playing",
                trackID: "track-9",
                durationSeconds: 210,
                crossfadeEnabled: true
            )
        )
        telemetry.flush()

        let entry = try #require(readEntries(url).last { $0.ev == "prepareNext" })
        #expect(entry.slots == 2)
        #expect(entry.footMB == 100.0)   // 104,857,600 bytes / 1 MiB
        #expect(entry.state == "playing")
        #expect(entry.trackID == "track-9")
        #expect(entry.cf == true)
    }

    @Test
    func sample_reusesCachedStateFromLastEvent() throws {
        let (telemetry, url) = makeTelemetry()
        telemetry.isEnabled = true

        telemetry.record(
            PlaybackTelemetryEvent(
                kind: .play,
                slots: 1,
                state: "playing",
                trackID: "track-1",
                durationSeconds: 180,
                crossfadeEnabled: false
            )
        )
        telemetry.sampleNow()
        telemetry.flush()

        let sample = try #require(readEntries(url).last { $0.ev == "sample" })
        #expect(sample.slots == 1)
        #expect(sample.state == "playing")
        #expect(sample.trackID == "track-1")
    }

    @Test
    func clear_removesTheLog() {
        let (telemetry, _) = makeTelemetry()
        telemetry.isEnabled = true
        telemetry.record(prepareNextEvent())
        telemetry.flush()
        #expect(telemetry.exportFileURL() != nil)

        telemetry.clear()
        telemetry.flush()

        #expect(telemetry.exportFileURL() == nil)
    }

    @Test
    func rotation_boundsGrowthAndKeepsRecentData() {
        let (telemetry, url) = makeTelemetry(maxBytes: 400)
        telemetry.isEnabled = true

        for _ in 0..<60 {
            telemetry.record(prepareNextEvent())
        }
        telemetry.flush()

        // A single-backup rotation caps disk growth (it drops data older than one
        // backup by design) while retaining recent records and never exceeding ~2x cap.
        #expect(FileManager.default.fileExists(atPath: telemetry.previousFileURL.path))
        let combined = fileSize(url) + fileSize(telemetry.previousFileURL)
        #expect(combined <= 400 * 3)
        #expect(!(readEntries(url) + readEntries(telemetry.previousFileURL)).isEmpty)
    }

    // MARK: - Helpers

    private func makeTelemetry(
        footprintBytes: UInt64 = 50_000_000,
        availableBytes: UInt64 = 0,
        maxBytes: Int = 5_000_000
    ) -> (PlaybackTelemetry, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("telemetry.jsonl", isDirectory: false)
        let defaults = UserDefaults(suiteName: "telemetry-test-\(UUID().uuidString)")!
        let telemetry = PlaybackTelemetry(
            probe: StubMemoryProbe(footprint: footprintBytes, available: availableBytes),
            fileURL: url,
            fileManager: .default,
            maxBytes: maxBytes,
            defaults: defaults
        )
        return (telemetry, url)
    }

    private func prepareNextEvent() -> PlaybackTelemetryEvent {
        PlaybackTelemetryEvent(
            kind: .prepareNext,
            slots: 2,
            state: "playing",
            trackID: "track-1",
            durationSeconds: 200,
            crossfadeEnabled: true
        )
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    private func readEntries(_ url: URL) -> [TelemetryEntry] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(TelemetryEntry.self, from: Data($0.utf8)) }
    }
}

private struct StubMemoryProbe: MemoryProbing {
    let footprint: UInt64
    let available: UInt64
    func footprintBytes() -> UInt64 { footprint }
    func availableBytes() -> UInt64 { available }
}
