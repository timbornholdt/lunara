import Foundation

struct AlphabetSection<Item>: Identifiable {
    let id: String
    let items: [Item]
}

enum AlphabetSectionBuilder {
    static func sections<Item>(
        from items: [Item],
        key: (Item) -> String
    ) -> [AlphabetSection<Item>] {
        var order: [String] = []
        var buckets: [String: [Item]] = [:]

        for item in items {
            let letter = sectionKey(for: key(item))
            if buckets[letter] == nil {
                order.append(letter)
                buckets[letter] = []
            }
            buckets[letter]?.append(item)
        }

        return order.compactMap { letter in
            guard let items = buckets[letter], !items.isEmpty else { return nil }
            return AlphabetSection(id: letter, items: items)
        }
    }

    static func sectionKey(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstScalar = trimmed.unicodeScalars.first else { return "#" }
        let first = String(firstScalar).uppercased()
        if first.rangeOfCharacter(from: CharacterSet.letters) != nil {
            return first
        }
        return "#"
    }
}
