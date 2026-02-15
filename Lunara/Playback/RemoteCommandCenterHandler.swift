import MediaPlayer

struct RemoteCommandHandlers {
    let onPlay: () -> Void
    let onPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
}

protocol RemoteCommandCenterHandling {
    func configure(handlers: RemoteCommandHandlers)
    func teardown()
}

protocol RemoteCommanding: AnyObject {
    var isEnabled: Bool { get set }

    @discardableResult
    func addHandler(_ handler: @escaping () -> MPRemoteCommandHandlerStatus) -> Any

    func removeHandler(_ target: Any)
}

extension MPRemoteCommand: RemoteCommanding {
    @discardableResult
    func addHandler(_ handler: @escaping () -> MPRemoteCommandHandlerStatus) -> Any {
        addTarget { _ in
            handler()
        }
    }

    func removeHandler(_ target: Any) {
        removeTarget(target)
    }
}

protocol RemoteCommandCenterProviding {
    var playCommand: RemoteCommanding { get }
    var pauseCommand: RemoteCommanding { get }
    var nextTrackCommand: RemoteCommanding { get }
    var previousTrackCommand: RemoteCommanding { get }
}

struct SystemRemoteCommandCenterProvider: RemoteCommandCenterProviding {
    private let center: MPRemoteCommandCenter

    init(center: MPRemoteCommandCenter = .shared()) {
        self.center = center
    }

    var playCommand: RemoteCommanding { center.playCommand }
    var pauseCommand: RemoteCommanding { center.pauseCommand }
    var nextTrackCommand: RemoteCommanding { center.nextTrackCommand }
    var previousTrackCommand: RemoteCommanding { center.previousTrackCommand }
}

final class RemoteCommandCenterHandler: RemoteCommandCenterHandling {
    private let center: RemoteCommandCenterProviding

    private var isConfigured = false
    private var playToken: Any?
    private var pauseToken: Any?
    private var nextToken: Any?
    private var previousToken: Any?

    init(center: RemoteCommandCenterProviding = SystemRemoteCommandCenterProvider()) {
        self.center = center
    }

    func configure(handlers: RemoteCommandHandlers) {
        if isConfigured {
            teardown()
        }

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        playToken = center.playCommand.addHandler {
            handlers.onPlay()
            return .success
        }
        pauseToken = center.pauseCommand.addHandler {
            handlers.onPause()
            return .success
        }
        nextToken = center.nextTrackCommand.addHandler {
            handlers.onNext()
            return .success
        }
        previousToken = center.previousTrackCommand.addHandler {
            handlers.onPrevious()
            return .success
        }

        isConfigured = true
    }

    func teardown() {
        guard isConfigured else { return }

        if let playToken {
            center.playCommand.removeHandler(playToken)
        }
        if let pauseToken {
            center.pauseCommand.removeHandler(pauseToken)
        }
        if let nextToken {
            center.nextTrackCommand.removeHandler(nextToken)
        }
        if let previousToken {
            center.previousTrackCommand.removeHandler(previousToken)
        }

        center.playCommand.isEnabled = false
        center.pauseCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false

        playToken = nil
        pauseToken = nil
        nextToken = nil
        previousToken = nil
        isConfigured = false
    }
}
