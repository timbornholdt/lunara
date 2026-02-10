import SwiftUI

struct ArtistArtworkView: View {
    let artist: PlexArtist
    let palette: LunaraTheme.PaletteColors?
    let size: ArtworkSize

    init(artist: PlexArtist, palette: LunaraTheme.PaletteColors? = nil, size: ArtworkSize = .detail) {
        self.artist = artist
        self.palette = palette
        self.size = size
    }

    var body: some View {
        let placeholder = palette?.raised ?? Color.gray.opacity(0.2)
        let secondaryText = palette?.textSecondary ?? Color.secondary

        if let request = artworkRequest() {
            ArtworkView(
                request: request,
                placeholder: placeholder,
                secondaryText: secondaryText
            )
        } else {
            placeholder
                .overlay(Text("No Art").font(.caption).foregroundStyle(secondaryText))
        }
    }

    private func artworkRequest() -> ArtworkRequest? {
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = ArtworkRequestBuilder(baseURL: baseURL, token: token)
        return builder.artistRequest(for: artist, size: size)
    }
}
