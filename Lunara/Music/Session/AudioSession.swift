import AVFoundation
import Foundation

protocol AudioSessionProtocol: AnyObject {
    var onInterruptionBegan: (() -> Void)? { get set }
    var onInterruptionEnded: ((Bool) -> Void)? { get set }

    func configureForPlayback() throws
}

protocol AudioSessionType: AnyObject {
    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionType {}

protocol NotificationCenterType: AnyObject {
    @discardableResult
    func addObserver(
        forName name: Notification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol

    func removeObserver(_ observer: Any)
}

extension NotificationCenter: NotificationCenterType {}

final class AudioSession: AudioSessionProtocol {

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?

    private let audioSession: AudioSessionType
    private let notificationCenter: NotificationCenterType
    private var interruptionObserver: NSObjectProtocol?

    init(
        audioSession: AudioSessionType = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenterType = NotificationCenter.default
    ) {
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
        }
    }

    func configureForPlayback() throws {
        try audioSession.setCategory(.playback, mode: .default, options: [])
        try audioSession.setActive(true, options: [])

        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
        }

        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue)
        else {
            return
        }

        switch interruptionType {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            onInterruptionEnded?(options.contains(.shouldResume))
        @unknown default:
            break
        }
    }
}
