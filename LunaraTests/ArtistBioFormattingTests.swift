import Foundation
import Testing
@testable import Lunara

/// Lunara-2z2: bio text renders as real paragraphs, not one block.
@MainActor
struct ArtistBioFormattingTests {
    @Test
    func paragraphs_splitOnNewlinesAndDropBlanks() {
        let bio = "First paragraph.\n\nSecond paragraph.\n   \nThird."
        #expect(ArtistDetailView.bioParagraphs(of: bio) == [
            "First paragraph.", "Second paragraph.", "Third."
        ])
    }

    @Test
    func paragraphs_singleBlockPassesThrough() {
        #expect(ArtistDetailView.bioParagraphs(of: "Just one block.") == ["Just one block."])
    }
}
