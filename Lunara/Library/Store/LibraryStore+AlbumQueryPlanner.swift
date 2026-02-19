import Foundation
import GRDB

extension LibraryStore {
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        let plan = AlbumQueryPlan(filter: filter)
        return try await dbQueue.read { db in
            let records = try AlbumRecord.fetchAll(db, sql: plan.sql, arguments: plan.arguments)
            return records.map(\.model)
        }
    }
}

private struct AlbumQueryPlan {
    let sql: String
    let arguments: StatementArguments

    init(filter: AlbumQueryFilter) {
        var predicates: [String] = []
        var arguments = StatementArguments()

        if let textQuery = Self.normalizedTextQuery(from: filter.textQuery) {
            let pattern = LibraryStoreSearchNormalizer.likeContainsPattern(for: textQuery)
            predicates.append("(albums.titleSearch LIKE ? ESCAPE '\\' OR albums.artistNameSearch LIKE ? ESCAPE '\\')")
            arguments += [pattern, pattern]
        }

        if let yearRange = filter.yearRange {
            predicates.append("albums.year >= ? AND albums.year <= ?")
            arguments += [yearRange.lowerBound, yearRange.upperBound]
        }

        Self.appendTagPredicate(kind: .genre, tags: filter.genreTags, to: &predicates, arguments: &arguments)
        Self.appendTagPredicate(kind: .style, tags: filter.styleTags, to: &predicates, arguments: &arguments)
        Self.appendTagPredicate(kind: .mood, tags: filter.moodTags, to: &predicates, arguments: &arguments)
        Self.appendRelationPredicate(
            tableName: "album_artists",
            columnName: "artistID",
            values: Self.normalizedIDs(filter.artistIDs),
            to: &predicates,
            arguments: &arguments
        )
        Self.appendRelationPredicate(
            tableName: "album_collections",
            columnName: "collectionID",
            values: Self.normalizedIDs(filter.collectionIDs),
            to: &predicates,
            arguments: &arguments
        )

        var sql = "SELECT albums.* FROM albums"
        if !predicates.isEmpty {
            sql += " WHERE " + predicates.joined(separator: " AND ")
        }
        sql += " ORDER BY albums.artistName ASC, albums.title ASC, albums.plexID ASC"

        self.sql = sql
        self.arguments = arguments
    }

    private static func appendTagPredicate(
        kind: LibraryTagKind,
        tags: [String],
        to predicates: inout [String],
        arguments: inout StatementArguments
    ) {
        let normalizedTags = normalizedTags(tags)
        guard !normalizedTags.isEmpty else {
            return
        }

        let placeholders = String(repeating: "?,", count: normalizedTags.count).dropLast()
        predicates.append(
            """
            albums.plexID IN (
                SELECT album_tags.albumID
                FROM album_tags
                INNER JOIN tags ON tags.id = album_tags.tagID
                WHERE tags.kind = ? AND tags.normalizedName IN (\(placeholders))
                GROUP BY album_tags.albumID
                HAVING COUNT(DISTINCT tags.normalizedName) = ?
            )
            """
        )
        arguments += [kind.rawValue]
        for tag in normalizedTags {
            arguments += [tag]
        }
        arguments += [normalizedTags.count]
    }

    private static func appendRelationPredicate(
        tableName: String,
        columnName: String,
        values: [String],
        to predicates: inout [String],
        arguments: inout StatementArguments
    ) {
        guard !values.isEmpty else {
            return
        }

        let placeholders = String(repeating: "?,", count: values.count).dropLast()
        predicates.append(
            """
            albums.plexID IN (
                SELECT albumID
                FROM \(tableName)
                WHERE \(columnName) IN (\(placeholders))
                GROUP BY albumID
                HAVING COUNT(DISTINCT \(columnName)) = ?
            )
            """
        )
        for value in values {
            arguments += [value]
        }
        arguments += [values.count]
    }

    private static func normalizedTextQuery(from rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let normalized = LibraryStoreSearchNormalizer.normalize(rawValue)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        let normalized = values
            .map(LibraryStoreSearchNormalizer.normalize)
            .filter { !$0.isEmpty }
        return Array(Set(normalized)).sorted()
    }

    private static func normalizedIDs(_ values: [String]) -> [String] {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(normalized)).sorted()
    }
}
