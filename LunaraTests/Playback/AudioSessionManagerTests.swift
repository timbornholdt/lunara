import AVFoundation
import Testing
@testable import Lunara

struct AudioSessionManagerTests {
    @Test func interruptionBeganInvokesCallback() {
        let center = NotificationCenter()
        let manager = AudioSessionManager(notificationCenter: center)
        var received: AudioSessionInterruption?
        manager.onInterruption = { received = $0 }

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )

        guard case .began = received else {
            Issue.record("Expected .began, got \(String(describing: received))")
            return
        }
    }

    @Test func interruptionEndedWithShouldResumeInvokesCallback() {
        let center = NotificationCenter()
        let manager = AudioSessionManager(notificationCenter: center)
        var received: AudioSessionInterruption?
        manager.onInterruption = { received = $0 }

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )

        guard case .ended(let shouldResume) = received else {
            Issue.record("Expected .ended, got \(String(describing: received))")
            return
        }
        #expect(shouldResume == true)
    }

    @Test func interruptionEndedWithoutShouldResumeInvokesCallback() {
        let center = NotificationCenter()
        let manager = AudioSessionManager(notificationCenter: center)
        var received: AudioSessionInterruption?
        manager.onInterruption = { received = $0 }

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
            ]
        )

        guard case .ended(let shouldResume) = received else {
            Issue.record("Expected .ended, got \(String(describing: received))")
            return
        }
        #expect(shouldResume == false)
    }

    @Test func missingUserInfoDoesNotInvokeCallback() {
        let center = NotificationCenter()
        let manager = AudioSessionManager(notificationCenter: center)
        var callbackInvoked = false
        manager.onInterruption = { _ in callbackInvoked = true }

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: nil
        )

        #expect(callbackInvoked == false)
    }
}
