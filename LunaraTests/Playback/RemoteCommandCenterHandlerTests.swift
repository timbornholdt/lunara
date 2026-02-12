import MediaPlayer
import Testing
@testable import Lunara

struct RemoteCommandCenterHandlerTests {
    @Test func configureRegistersHandlersOnce() {
        let center = StubRemoteCommandCenter()
        let handler = RemoteCommandCenterHandler(center: center)
        var playCount = 0

        handler.configure(
            handlers: RemoteCommandHandlers(
                onPlay: { playCount += 1 },
                onPause: {},
                onNext: {},
                onPrevious: {}
            )
        )
        handler.configure(
            handlers: RemoteCommandHandlers(
                onPlay: { playCount += 1 },
                onPause: {},
                onNext: {},
                onPrevious: {}
            )
        )

        #expect(center.playCommandStub.addCallCount == 1)
        #expect(center.pauseCommandStub.addCallCount == 1)
        #expect(center.nextCommandStub.addCallCount == 1)
        #expect(center.previousCommandStub.addCallCount == 1)

        center.playCommandStub.trigger()
        #expect(playCount == 1)
    }

    @Test func teardownRemovesHandlersAndDisablesCommands() {
        let center = StubRemoteCommandCenter()
        let handler = RemoteCommandCenterHandler(center: center)

        handler.configure(
            handlers: RemoteCommandHandlers(
                onPlay: {},
                onPause: {},
                onNext: {},
                onPrevious: {}
            )
        )
        handler.teardown()
        handler.teardown()

        #expect(center.playCommandStub.removeCallCount == 1)
        #expect(center.pauseCommandStub.removeCallCount == 1)
        #expect(center.nextCommandStub.removeCallCount == 1)
        #expect(center.previousCommandStub.removeCallCount == 1)
        #expect(center.playCommandStub.isEnabled == false)
        #expect(center.pauseCommandStub.isEnabled == false)
        #expect(center.nextCommandStub.isEnabled == false)
        #expect(center.previousCommandStub.isEnabled == false)
    }
}

private final class StubRemoteCommandCenter: RemoteCommandCenterProviding {
    let playCommandStub = StubRemoteCommand()
    let pauseCommandStub = StubRemoteCommand()
    let nextCommandStub = StubRemoteCommand()
    let previousCommandStub = StubRemoteCommand()

    var playCommand: RemoteCommanding { playCommandStub }
    var pauseCommand: RemoteCommanding { pauseCommandStub }
    var nextTrackCommand: RemoteCommanding { nextCommandStub }
    var previousTrackCommand: RemoteCommanding { previousCommandStub }
}

private final class StubRemoteCommand: RemoteCommanding {
    var isEnabled = false
    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0
    private var handlers: [UUID: () -> MPRemoteCommandHandlerStatus] = [:]

    func addHandler(_ handler: @escaping () -> MPRemoteCommandHandlerStatus) -> Any {
        addCallCount += 1
        let token = UUID()
        handlers[token] = handler
        return token
    }

    func removeHandler(_ target: Any) {
        removeCallCount += 1
        guard let token = target as? UUID else { return }
        handlers[token] = nil
    }

    func trigger() {
        _ = handlers.values.first?()
    }
}
