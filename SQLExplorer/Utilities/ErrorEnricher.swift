import Foundation

// MARK: - Types

enum ErrorCategory {
    case syntax
    case objectNotFound
    case permission
    case connection
    case execution
    case validation
    case unknown
}

struct ErrorSuggestion {
    let text: String
    let action: SuggestionAction
}

enum SuggestionAction {
    case insertText(String)
    case replaceQuery(String)
    case copyText(String)
}

struct EnrichedError {
    let message: String
    let category: ErrorCategory
    let suggestions: [ErrorSuggestion]
    let validationIssues: [SQLValidationIssue]
}

// MARK: - Enricher

/// Analyzes sanitized error messages and produces categorized errors with actionable suggestions.
enum ErrorEnricher {

    @MainActor
    static func enrich(
        sanitizedMessage: String,
        sql: String,
        schema: SchemaCache,
        validationIssues: [SQLValidationIssue] = []
    ) -> EnrichedError {
        let lower = sanitizedMessage.lowercased()

        // Pattern: "Must specify table to select from"
        if lower.contains("must specify table") || lower.contains("missing a from clause") {
            let tables = Array(schema.tables.prefix(8))
            let suggestions = tables.map { table in
                ErrorSuggestion(text: table, action: .insertText("FROM \(table)"))
            }
            return EnrichedError(
                message: sanitizedMessage,
                category: .syntax,
                suggestions: suggestions,
                validationIssues: validationIssues)
        }

        // Pattern: "Invalid object name 'xxx'"
        if let objectName = extractQuoted(from: lower, after: "invalid object name") {
            let matches = fuzzyMatch(objectName, in: schema.tables + schema.views, limit: 5)
            let suggestions = matches.map { match in
                ErrorSuggestion(text: match, action: .insertText(match))
            }
            return EnrichedError(
                message: sanitizedMessage,
                category: .objectNotFound,
                suggestions: suggestions,
                validationIssues: validationIssues)
        }

        // Pattern: "Invalid column name 'xxx'"
        if lower.contains("invalid column name") {
            return EnrichedError(
                message: sanitizedMessage,
                category: .objectNotFound,
                suggestions: [],
                validationIssues: validationIssues)
        }

        // Pattern: "Could not find stored procedure 'xxx'"
        if let procName = extractQuoted(from: lower, after: "could not find stored procedure") {
            let matches = fuzzyMatch(procName, in: schema.storedProcedures, limit: 5)
            let suggestions = matches.map { match in
                ErrorSuggestion(text: match, action: .insertText(match))
            }
            return EnrichedError(
                message: sanitizedMessage,
                category: .objectNotFound,
                suggestions: suggestions,
                validationIssues: validationIssues)
        }

        // Pattern: Permission errors
        if lower.contains("permission denied") || lower.contains("not have permission") || lower.contains("access denied") {
            return EnrichedError(
                message: sanitizedMessage,
                category: .permission,
                suggestions: [],
                validationIssues: validationIssues)
        }

        // Pattern: Connection errors
        if lower.contains("login timeout") || lower.contains("connection lost") ||
           lower.contains("tcp provider") || lower.contains("communication link") ||
           lower.contains("server is not found") || lower.contains("network-related") {
            return EnrichedError(
                message: sanitizedMessage,
                category: .connection,
                suggestions: [],
                validationIssues: validationIssues)
        }

        // Pattern: Syntax errors from SQL Server
        if lower.contains("incorrect syntax") || lower.contains("syntax error") {
            return EnrichedError(
                message: sanitizedMessage,
                category: .syntax,
                suggestions: [],
                validationIssues: validationIssues)
        }

        // Default
        return EnrichedError(
            message: sanitizedMessage,
            category: .unknown,
            suggestions: [],
            validationIssues: validationIssues)
    }

    // MARK: - Helpers

    /// Extract a quoted name from an error message, e.g. "Invalid object name 'dbo.Foo'" → "dbo.Foo"
    private static func extractQuoted(from message: String, after prefix: String) -> String? {
        guard let prefixRange = message.range(of: prefix) else { return nil }
        let afterPrefix = message[prefixRange.upperBound...]
        guard let quoteStart = afterPrefix.firstIndex(of: "'") else { return nil }
        let nameStart = afterPrefix.index(after: quoteStart)
        guard let quoteEnd = afterPrefix[nameStart...].firstIndex(of: "'") else { return nil }
        let name = String(afterPrefix[nameStart..<quoteEnd])
        return name.isEmpty ? nil : name
    }

    /// Find close matches using Levenshtein distance and prefix matching
    private static func fuzzyMatch(_ target: String, in candidates: [String], limit: Int) -> [String] {
        let targetLower = target.lowercased()
        var scored: [(String, Int)] = []

        for candidate in candidates {
            let candidateLower = candidate.lowercased()
            if candidateLower == targetLower { continue } // Skip exact match (it was already "not found")
            if candidateLower.hasPrefix(targetLower.prefix(3)) {
                scored.append((candidate, 0))
            } else {
                let dist = levenshtein(targetLower, candidateLower)
                if dist <= 4 {
                    scored.append((candidate, dist))
                }
            }
        }

        return scored
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }
}
