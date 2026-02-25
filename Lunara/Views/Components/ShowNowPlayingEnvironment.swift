import SwiftUI

private struct ShowNowPlayingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showNowPlaying: Binding<Bool> {
        get { self[ShowNowPlayingKey.self] }
        set { self[ShowNowPlayingKey.self] = newValue }
    }
}
