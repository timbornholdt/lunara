import Testing
@testable import Lunara

struct AlphabetSectionBuilderTests {
    @Test
    func sectionKeyUsesLettersWhenAvailable() {
        let key = AlphabetSectionBuilder.sectionKey(for: "The National")
        #expect(key == "T")
    }

    @Test
    func sectionKeyFallsBackToNumberBucket() {
        let key = AlphabetSectionBuilder.sectionKey(for: "2Pac")
        #expect(key == "#")
    }

    @Test
    func sectionsPreserveInputOrder() {
        let items = ["Arcade Fire", "Bowie", "The National"]
        let sections = AlphabetSectionBuilder.sections(from: items) { $0 }
        let ids = sections.map(\.id)
        #expect(ids == ["A", "B", "T"])
    }
}
