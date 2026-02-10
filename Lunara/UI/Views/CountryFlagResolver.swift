import Foundation

enum CountryFlagResolver {
    static func flag(for countryCode: String?) -> String? {
        guard let countryCode else { return nil }
        let trimmed = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 2 else { return nil }
        let scalars = trimmed.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let flagScalar = UnicodeScalar(127397 + scalar.value) else { return nil }
            return flagScalar
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }
}
