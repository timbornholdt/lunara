import AVFoundation
import Foundation
import Testing
@testable import Lunara

@MainActor
struct AVQueuePlayerAdapterTests {
    @Test func setQueueNotifiesCurrentIndex() async throws {
        let player = AVQueuePlayer()
        let adapter = AVQueuePlayerAdapter(player: player)
        var receivedIndex: Int?
        adapter.onItemChanged = { receivedIndex = $0 }

        adapter.setQueue(urls: [
            URL(string: "https://example.com/1.mp3")!,
            URL(string: "https://example.com/2.mp3")!
        ])

        #expect(receivedIndex == 0)
    }

    @Test func endOfItemAdvancesIndex() async throws {
        let player = AVQueuePlayer()
        let adapter = AVQueuePlayerAdapter(player: player)
        var receivedIndices: [Int] = []
        adapter.onItemChanged = { receivedIndices.append($0) }
        adapter.setQueue(urls: [
            URL(string: "https://example.com/1.mp3")!,
            URL(string: "https://example.com/2.mp3")!
        ])

        let currentItem = try #require(player.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: currentItem)

        #expect(receivedIndices == [0, 1])
    }

    @Test func failureNotificationTriggersCallback() async throws {
        let player = AVQueuePlayer()
        let adapter = AVQueuePlayerAdapter(player: player)
        var failedIndex: Int?
        adapter.onItemFailed = { failedIndex = $0 }
        adapter.setQueue(urls: [
            URL(string: "https://example.com/1.mp3")!
        ])

        let currentItem = try #require(player.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: currentItem)

        #expect(failedIndex == 0)
    }

    @Test func replaceCurrentItemSwapsURL() async throws {
        let player = AVQueuePlayer()
        let adapter = AVQueuePlayerAdapter(player: player)
        adapter.setQueue(urls: [
            URL(string: "https://example.com/1.mp3")!
        ])

        let fallbackURL = URL(string: "https://example.com/fallback.m3u8")!
        adapter.replaceCurrentItem(url: fallbackURL)

        let asset = try #require(player.currentItem?.asset as? AVURLAsset)
        #expect(asset.url == fallbackURL)
    }
}
