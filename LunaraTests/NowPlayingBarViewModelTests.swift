import Foundation
import Testing
@testable import Lunara

/// Lunara-m73: bar/accessory visibility must not flap during playback startup.
/// It latches synchronously on the queue's hasPlaybackBegun (set in playNow)
/// instead of racing the async engine-state observer — mid-start engine idle
/// bounces used to disable the iOS 26 accessory, tearing down the Now Playing
/// sheet host in a dismiss/re-present loop.
@MainActor
struct NowPlayingBarViewModelTests {
    @Test
    func isVisible_immediatelyAfterUserPlay_whileEngineStillIdle() {
        let (viewModel, queue, engine) = makeSubject()
        queue.currentItem = makeItem(id: "t1")
        queue.hasPlaybackBegun = true
        engine.playbackState = .idle // URL resolution still in flight

        #expect(viewModel.isVisible)
    }

    @Test
    func isVisible_staysTrueThroughMidStartIdleBounces() {
        let (viewModel, queue, engine) = makeSubject()
        queue.currentItem = makeItem(id: "t1")
        queue.hasPlaybackBegun = true

        engine.playbackState = .buffering
        #expect(viewModel.isVisible)
        engine.playbackState = .idle // engine bounce between buffering and playing
        #expect(viewModel.isVisible)
        engine.playbackState = .playing
        #expect(viewModel.isVisible)
    }

    @Test
    func isVisible_falseForRestoredQueueBeforeExplicitPlay() {
        let (viewModel, queue, engine) = makeSubject()
        queue.currentItem = makeItem(id: "t1")
        queue.hasPlaybackBegun = false
        engine.playbackState = .idle

        #expect(!viewModel.isVisible)
    }

    @Test
    func isVisible_falseWithEmptyQueue() {
        let (viewModel, queue, engine) = makeSubject()
        queue.currentItem = nil
        queue.hasPlaybackBegun = true
        engine.playbackState = .idle

        #expect(!viewModel.isVisible)
    }

    private func makeSubject() -> (NowPlayingBarViewModel, NowPlayingQueueMock, PlaybackEngineMock) {
        let queue = NowPlayingQueueMock()
        let engine = PlaybackEngineMock()
        let resolver = NowPlayingResolver(library: NowPlayingLibraryMock(), artwork: ArtworkPipelineMock())
        let viewModel = NowPlayingBarViewModel(queueManager: queue, engine: engine, resolver: resolver)
        return (viewModel, queue, engine)
    }

    private func makeItem(id: String) -> QueueItem {
        QueueItem(trackID: id, streamKey: "/library/parts/\(id)/file.mp3", albumID: "al-1", trackNumber: 1)
    }
}
