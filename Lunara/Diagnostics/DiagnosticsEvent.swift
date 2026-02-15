import Foundation

enum DiagnosticsEvent {
    case appLaunch
    case playbackPlay(trackCount: Int, startIndex: Int)
    case playbackAudioStarted(trackKey: String)
    case playbackSkipNext
    case playbackSkipPrevious
    case playbackStateChange(trackKey: String, isPlaying: Bool)
    case playbackUISync(trackKey: String)
    case navigationTabChange(tab: String)
    case navigationScreenPush(screenType: String, key: String)
    case audioSessionInterruption(type: String)
    case scenePhaseChange(phase: String)
    case remoteCommand(command: String)

    var name: String {
        switch self {
        case .appLaunch: "app.launch"
        case .playbackPlay: "playback.play"
        case .playbackAudioStarted: "playback.audio_started"
        case .playbackSkipNext: "playback.skip_next"
        case .playbackSkipPrevious: "playback.skip_previous"
        case .playbackStateChange: "playback.state_change"
        case .playbackUISync: "playback.ui_sync"
        case .navigationTabChange: "navigation.tab_change"
        case .navigationScreenPush: "navigation.screen_push"
        case .audioSessionInterruption: "audio_session.interruption"
        case .scenePhaseChange: "app.scene_phase_change"
        case .remoteCommand: "remote.command"
        }
    }

    var data: [String: String] {
        switch self {
        case .appLaunch:
            return [:]
        case .playbackPlay(let trackCount, let startIndex):
            return ["trackCount": "\(trackCount)", "startIndex": "\(startIndex)"]
        case .playbackAudioStarted(let trackKey):
            return ["trackKey": trackKey]
        case .playbackSkipNext, .playbackSkipPrevious:
            return [:]
        case .playbackStateChange(let trackKey, let isPlaying):
            return ["trackKey": trackKey, "isPlaying": "\(isPlaying)"]
        case .playbackUISync(let trackKey):
            return ["trackKey": trackKey]
        case .navigationTabChange(let tab):
            return ["tab": tab]
        case .navigationScreenPush(let screenType, let key):
            return ["screenType": screenType, "key": key]
        case .audioSessionInterruption(let type):
            return ["type": type]
        case .scenePhaseChange(let phase):
            return ["phase": phase]
        case .remoteCommand(let command):
            return ["command": command]
        }
    }
}
