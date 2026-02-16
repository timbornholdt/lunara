import AVFoundation
import Foundation
import Testing
@testable import Lunara

struct AudioSessionTests {

    @Test
    func configureForPlayback_setsPlaybackCategoryDefaultModeAndActivatesSession() throws {
        let audioSessionSpy = AudioSessionSpy()
        let notificationCenterSpy = NotificationCenterSpy()
        let subject = AudioSession(audioSession: audioSessionSpy, notificationCenter: notificationCenterSpy)

        try subject.configureForPlayback()

        #expect(audioSessionSpy.setCategoryCallCount == 1)
        #expect(audioSessionSpy.lastCategory == .playback)
        #expect(audioSessionSpy.lastMode == .default)
        #expect(audioSessionSpy.lastCategoryOptions == [])

        #expect(audioSessionSpy.setActiveCallCount == 1)
        #expect(audioSessionSpy.lastActiveValue == true)
        #expect(audioSessionSpy.lastSetActiveOptions == [])

        #expect(notificationCenterSpy.addObserverCallCount == 1)
        #expect(notificationCenterSpy.lastObservedName == AVAudioSession.interruptionNotification)
    }

    @Test
    func interruptionNotification_whenBegan_callsOnInterruptionBegan() throws {
        let audioSessionSpy = AudioSessionSpy()
        let notificationCenterSpy = NotificationCenterSpy()
        let subject = AudioSession(audioSession: audioSessionSpy, notificationCenter: notificationCenterSpy)
        var beganCallCount = 0

        subject.onInterruptionBegan = { beganCallCount += 1 }

        try subject.configureForPlayback()

        notificationCenterSpy.emitInterruption(
            type: .began,
            options: []
        )

        #expect(beganCallCount == 1)
    }

    @Test
    func interruptionNotification_whenEndedWithShouldResumeOption_callsOnInterruptionEndedWithTrue() throws {
        let audioSessionSpy = AudioSessionSpy()
        let notificationCenterSpy = NotificationCenterSpy()
        let subject = AudioSession(audioSession: audioSessionSpy, notificationCenter: notificationCenterSpy)
        var receivedShouldResume: Bool?

        subject.onInterruptionEnded = { shouldResume in
            receivedShouldResume = shouldResume
        }

        try subject.configureForPlayback()

        notificationCenterSpy.emitInterruption(
            type: .ended,
            options: [.shouldResume]
        )

        #expect(receivedShouldResume == true)
    }

    @Test
    func interruptionNotification_whenEndedWithoutShouldResumeOption_callsOnInterruptionEndedWithFalse() throws {
        let audioSessionSpy = AudioSessionSpy()
        let notificationCenterSpy = NotificationCenterSpy()
        let subject = AudioSession(audioSession: audioSessionSpy, notificationCenter: notificationCenterSpy)
        var receivedShouldResume: Bool?

        subject.onInterruptionEnded = { shouldResume in
            receivedShouldResume = shouldResume
        }

        try subject.configureForPlayback()

        notificationCenterSpy.emitInterruption(
            type: .ended,
            options: []
        )

        #expect(receivedShouldResume == false)
    }

    @Test
    func configureForPlayback_whenCalledTwice_replacesExistingInterruptionObserver() throws {
        let audioSessionSpy = AudioSessionSpy()
        let notificationCenterSpy = NotificationCenterSpy()
        let subject = AudioSession(audioSession: audioSessionSpy, notificationCenter: notificationCenterSpy)

        try subject.configureForPlayback()
        let firstObserver = try #require(notificationCenterSpy.lastObserver)

        try subject.configureForPlayback()

        #expect(notificationCenterSpy.removeObserverCallCount == 1)
        #expect(notificationCenterSpy.removedObservers.first as? ObserverToken == firstObserver)
    }
}

private final class AudioSessionSpy: AudioSessionType {
    private(set) var setCategoryCallCount = 0
    private(set) var lastCategory: AVAudioSession.Category?
    private(set) var lastMode: AVAudioSession.Mode?
    private(set) var lastCategoryOptions: AVAudioSession.CategoryOptions?

    private(set) var setActiveCallCount = 0
    private(set) var lastActiveValue: Bool?
    private(set) var lastSetActiveOptions: AVAudioSession.SetActiveOptions?

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        setCategoryCallCount += 1
        lastCategory = category
        lastMode = mode
        lastCategoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        setActiveCallCount += 1
        lastActiveValue = active
        lastSetActiveOptions = options
    }
}

private final class NotificationCenterSpy: NotificationCenterType {
    private(set) var addObserverCallCount = 0
    private(set) var lastObservedName: Notification.Name?
    private(set) var lastObserver: ObserverToken?

    private(set) var removeObserverCallCount = 0
    private(set) var removedObservers: [Any] = []

    private var interruptionHandler: ((Notification) -> Void)?

    @discardableResult
    func addObserver(
        forName name: Notification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        addObserverCallCount += 1
        lastObservedName = name
        interruptionHandler = block

        let token = ObserverToken()
        lastObserver = token
        return token
    }

    func removeObserver(_ observer: Any) {
        removeObserverCallCount += 1
        removedObservers.append(observer)
    }

    func emitInterruption(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions
    ) {
        let notification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: type.rawValue,
                AVAudioSessionInterruptionOptionKey: options.rawValue,
            ]
        )

        interruptionHandler?(notification)
    }
}

private final class ObserverToken: NSObject {}
