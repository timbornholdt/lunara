import CoreFoundation
import SwiftUI
import Testing
@testable import Lunara

struct AlbumDetailTypographyTests {
    @Test
    func token_subtitleMetadata_usesPlayfairRegularSubheadline() {
        let token = AlbumDetailTypography.token(for: .subtitleMetadata)

        #expect(token.preferredFontName == "PlayfairDisplay-Regular")
        #expect(token.fallbackWeight == .regular)
        #expect(token.size == 17)
        #expect(token.relativeTextStyle == .subheadline)
        #expect(token.usesMonospacedDigits == false)
    }

    @Test
    func token_trackRows_usePlayfairAndMonospacedDigitsForNumbers() {
        let numberToken = AlbumDetailTypography.token(for: .trackNumber)
        let durationToken = AlbumDetailTypography.token(for: .trackDuration)

        #expect(numberToken.preferredFontName == "PlayfairDisplay-SemiBold")
        #expect(numberToken.usesMonospacedDigits == true)
        #expect(durationToken.preferredFontName == "PlayfairDisplay-Regular")
        #expect(durationToken.usesMonospacedDigits == true)
    }

    @Test
    func token_reviewAndPillText_usePlayfairFaces() {
        let reviewToken = AlbumDetailTypography.token(for: .reviewBody)
        let pillToken = AlbumDetailTypography.token(for: .pill)

        #expect(reviewToken.preferredFontName == "PlayfairDisplay-Regular")
        #expect(pillToken.preferredFontName == "PlayfairDisplay-SemiBold")
        #expect(pillToken.relativeTextStyle == .caption)
    }
}
