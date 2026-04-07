import Foundation

/// Escapes user-derived identifiers for safe interpolation into SQL Server queries.
/// Used for catalog queries where parameterized queries aren't available (FreeTDS db-lib).
enum SQLEscaping {
    /// Escape a value for use inside bracket-delimited identifiers: [value]
    /// Doubles any ] characters: myTable] → [myTable]]]
    static func bracketIdentifier(_ name: String) -> String {
        "[\(name.replacingOccurrences(of: "]", with: "]]"))]"
    }

    /// Escape a value for use inside single-quoted string literals: 'value'
    /// Doubles any ' characters: O'Brien → 'O''Brien'
    static func quotedString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    /// Build a safe OBJECT_ID reference: OBJECT_ID('[schema].[table]')
    /// Escapes both bracket identifiers and the outer single quotes.
    static func objectIdRef(schema: String, table: String) -> String {
        let escapedSchema = schema.replacingOccurrences(of: "]", with: "]]")
        let escapedTable = table.replacingOccurrences(of: "]", with: "]]")
        let inner = "[\(escapedSchema)].[\(escapedTable)]"
            .replacingOccurrences(of: "'", with: "''")
        return "OBJECT_ID('\(inner)')"
    }
}
