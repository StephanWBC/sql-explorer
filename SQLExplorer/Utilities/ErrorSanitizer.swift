import Foundation

/// Strips technical driver prefixes and wrapper text from SQL error messages,
/// leaving only the human-readable message.
enum ErrorSanitizer {
    /// Regex matching one or more leading `[bracketed segments]`
    /// e.g. `[Microsoft][ODBC Driver 18 for SQL Server][SQL Server]`
    private static let bracketPrefixRegex = try! NSRegularExpression(
        pattern: #"^\s*(\[.*?\]\s*)+"#)

    /// Known wrapper prefixes added by LocalizedError conformances
    private static let wrapperPrefixes = [
        "query failed: ",
        "connection failed: ",
    ]

    static func sanitize(_ rawMessage: String) -> String {
        var message = rawMessage

        // Strip leading [bracketed][driver][segments]
        let fullRange = NSRange(message.startIndex..., in: message)
        if let match = bracketPrefixRegex.firstMatch(in: message, range: fullRange) {
            let matchRange = Range(match.range, in: message)!
            message = String(message[matchRange.upperBound...])
        }

        // Strip known wrapper prefixes (case-insensitive)
        for prefix in wrapperPrefixes {
            if message.lowercased().hasPrefix(prefix) {
                message = String(message.dropFirst(prefix.count))
            }
        }

        // Trim whitespace
        message = message.trimmingCharacters(in: .whitespaces)

        // Ensure first character is capitalized
        if let first = message.first, first.isLowercase {
            message = first.uppercased() + message.dropFirst()
        }

        return message.isEmpty ? rawMessage : message
    }
}
