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
    case shuffleStarted(albumCount: Int)
    case shufflePhase1Complete(trackCount: Int, durationMs: Int)
    case shufflePhase2Complete(trackCount: Int, durationMs: Int)
    case playbackLatency(operation: String, durationMs: Int)

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
        case .shuffleStarted: "shuffle.started"
        case .shufflePhase1Complete: "shuffle.phase1_complete"
        case .shufflePhase2Complete: "shuffle.phase2_complete"
        case .playbackLatency: "playback.latency"
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
        case .shuffleStarted(let albumCount):
            return ["albumCount": "\(albumCount)"]
        case .shufflePhase1Complete(let trackCount, let durationMs):
            return ["trackCount": "\(trackCount)", "durationMs": "\(durationMs)"]
        case .shufflePhase2Complete(let trackCount, let durationMs):
            return ["trackCount": "\(trackCount)", "durationMs": "\(durationMs)"]
        case .playbackLatency(let operation, let durationMs):
            return ["operation": operation, "durationMs": "\(durationMs)"]
        }
    }
}
