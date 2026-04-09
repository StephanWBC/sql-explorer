import Foundation

struct SQLValidationIssue {
    enum Severity { case error, warning }
    let severity: Severity
    let message: String
    let suggestion: String?
}

/// Lightweight SQL pre-validator that catches common mistakes before hitting the server.
/// Uses SchemaCache data for context-aware suggestions.
enum SQLPreValidator {

    /// Validate SQL and return any issues found.
    /// Only `.error` severity should block execution; `.warning` is informational.
    @MainActor
    static func validate(_ sql: String, schema: SchemaCache) -> [SQLValidationIssue] {
        let stripped = stripCommentsAndStrings(sql)
        let tokens = tokenize(stripped)
        var issues: [SQLValidationIssue] = []

        // Rule 1: Unclosed string literal
        if hasUnclosedString(sql) {
            issues.append(SQLValidationIssue(
                severity: .error,
                message: "Unclosed string literal — you have a missing closing quote ( ' ).",
                suggestion: nil))
        }

        // Rule 2: Unclosed parenthesis
        let (openCount, closeCount) = countParentheses(stripped)
        if openCount != closeCount {
            let diff = openCount - closeCount
            if diff > 0 {
                issues.append(SQLValidationIssue(
                    severity: .warning,
                    message: "Missing \(diff) closing parenthes\(diff == 1 ? "is" : "es").",
                    suggestion: nil))
            } else {
                issues.append(SQLValidationIssue(
                    severity: .warning,
                    message: "Extra \(-diff) closing parenthes\(-diff == 1 ? "is" : "es") without matching open.",
                    suggestion: nil))
            }
        }

        // Rule 3: SELECT without FROM
        if let issue = checkSelectWithoutFrom(tokens, schema: schema) {
            issues.append(issue)
        }

        // Rule 4: Unrecognized table after FROM/JOIN
        issues.append(contentsOf: checkUnrecognizedTables(tokens, schema: schema))

        // Rule 5: Unrecognized EXEC procedure
        issues.append(contentsOf: checkUnrecognizedProcedures(tokens, schema: schema))

        return issues
    }

    // MARK: - Individual Rules

    private static func hasUnclosedString(_ sql: String) -> Bool {
        var inString = false
        var i = sql.startIndex
        while i < sql.endIndex {
            let ch = sql[i]
            if ch == "'" {
                if inString {
                    // Check for escaped quote ('')
                    let next = sql.index(after: i)
                    if next < sql.endIndex && sql[next] == "'" {
                        i = sql.index(after: next)
                        continue
                    }
                    inString = false
                } else {
                    inString = true
                }
            }
            i = sql.index(after: i)
        }
        return inString
    }

    private static func countParentheses(_ stripped: String) -> (open: Int, close: Int) {
        var open = 0, close = 0
        for ch in stripped {
            if ch == "(" { open += 1 }
            else if ch == ")" { close += 1 }
        }
        return (open, close)
    }

    @MainActor
    private static func checkSelectWithoutFrom(_ tokens: [String], schema: SchemaCache) -> SQLValidationIssue? {
        let upper = tokens.map { $0.uppercased() }

        // Find SELECT that isn't followed by FROM somewhere before the next statement boundary
        var i = 0
        while i < upper.count {
            if upper[i] == "SELECT" {
                // Scan forward for FROM or statement end
                var hasFrom = false
                var hasColumnRef = false
                var j = i + 1
                while j < upper.count {
                    let tok = upper[j]
                    // Statement boundaries
                    if tok == ";" || tok == "GO" || tok == "INSERT" || tok == "UPDATE" || tok == "DELETE" || tok == "CREATE" || tok == "ALTER" || tok == "DROP" {
                        break
                    }
                    if tok == "FROM" {
                        hasFrom = true
                        break
                    }
                    // Check if it looks like a column reference (not a system function/literal)
                    if !isSystemExpression(tok) && !isKeyword(tok) && tok != "*" && tok != "," {
                        hasColumnRef = true
                    }
                    j += 1
                }

                // SELECT * without FROM is always an issue
                // SELECT with column-like identifiers without FROM is an issue
                if !hasFrom && (upper.contains(where: { i + 1 < upper.count && $0 == "*" }) || hasColumnRef) {
                    // Check if it's just "SELECT *" with no column context
                    let selectTokens = Array(upper[(i+1)..<min(j, upper.count)])
                    if selectTokens.first == "*" || hasColumnRef {
                        let tableSuggestions = Array(schema.tables.prefix(5))
                        let suggestion = tableSuggestions.isEmpty ? nil :
                            "Add a FROM clause. Available tables: " + tableSuggestions.joined(separator: ", ")
                        return SQLValidationIssue(
                            severity: .warning,
                            message: "SELECT statement appears to be missing a FROM clause.",
                            suggestion: suggestion)
                    }
                }
            }
            i += 1
        }
        return nil
    }

    @MainActor
    private static func checkUnrecognizedTables(_ tokens: [String], schema: SchemaCache) -> [SQLValidationIssue] {
        let upper = tokens.map { $0.uppercased() }
        let allObjects = Set((schema.tables + schema.views).map { $0.uppercased() })
        var issues: [SQLValidationIssue] = []

        for (idx, tok) in upper.enumerated() {
            if (tok == "FROM" || tok == "JOIN") && idx + 1 < upper.count {
                let tableName = tokens[idx + 1]  // Preserve original casing
                let tableUpper = tableName.uppercased()

                // Skip subqueries, temp tables, table variables, CTEs
                if tableName.hasPrefix("(") || tableName.hasPrefix("#") || tableName.hasPrefix("@") {
                    continue
                }
                // Skip 4-part names (linked servers)
                if tableName.components(separatedBy: ".").count > 3 { continue }
                // Skip if it looks like a keyword or alias
                if isKeyword(tableUpper) { continue }

                if !allObjects.contains(tableUpper) && !allObjects.isEmpty {
                    let suggestion = fuzzyMatch(tableUpper, in: schema.tables + schema.views, limit: 3)
                    issues.append(SQLValidationIssue(
                        severity: .warning,
                        message: "'\(tableName)' was not found in the schema cache.",
                        suggestion: suggestion.isEmpty ? nil :
                            "Did you mean: " + suggestion.joined(separator: ", ") + "?"))
                }
            }
        }
        return issues
    }

    @MainActor
    private static func checkUnrecognizedProcedures(_ tokens: [String], schema: SchemaCache) -> [SQLValidationIssue] {
        let upper = tokens.map { $0.uppercased() }
        let allProcs = Set(schema.storedProcedures.map { $0.uppercased() })
        var issues: [SQLValidationIssue] = []

        for (idx, tok) in upper.enumerated() {
            if (tok == "EXEC" || tok == "EXECUTE") && idx + 1 < upper.count {
                let procName = tokens[idx + 1]
                let procUpper = procName.uppercased()

                if procName.hasPrefix("@") || procName.hasPrefix("#") { continue }
                if isKeyword(procUpper) { continue }

                if !allProcs.contains(procUpper) && !allProcs.isEmpty {
                    let suggestion = fuzzyMatch(procUpper, in: schema.storedProcedures, limit: 3)
                    issues.append(SQLValidationIssue(
                        severity: .warning,
                        message: "Stored procedure '\(procName)' was not found in the schema cache.",
                        suggestion: suggestion.isEmpty ? nil :
                            "Did you mean: " + suggestion.joined(separator: ", ") + "?"))
                }
            }
        }
        return issues
    }

    // MARK: - Tokenizer

    /// Strip comments and string literal contents, replacing them with placeholders.
    private static func stripCommentsAndStrings(_ sql: String) -> String {
        var result = ""
        var i = sql.startIndex
        while i < sql.endIndex {
            let ch = sql[i]

            // Single-line comment
            if ch == "-" {
                let next = sql.index(after: i)
                if next < sql.endIndex && sql[next] == "-" {
                    // Skip to end of line
                    while i < sql.endIndex && sql[i] != "\n" { i = sql.index(after: i) }
                    result += " "
                    continue
                }
            }

            // Multi-line comment
            if ch == "/" {
                let next = sql.index(after: i)
                if next < sql.endIndex && sql[next] == "*" {
                    i = sql.index(after: next)
                    while i < sql.endIndex {
                        if sql[i] == "*" {
                            let afterStar = sql.index(after: i)
                            if afterStar < sql.endIndex && sql[afterStar] == "/" {
                                i = sql.index(after: afterStar)
                                break
                            }
                        }
                        i = sql.index(after: i)
                    }
                    result += " "
                    continue
                }
            }

            // String literal — keep quotes but blank out contents
            if ch == "'" {
                result += " "
                i = sql.index(after: i)
                while i < sql.endIndex {
                    if sql[i] == "'" {
                        let next = sql.index(after: i)
                        if next < sql.endIndex && sql[next] == "'" {
                            // Escaped quote — skip both
                            i = sql.index(after: next)
                            continue
                        }
                        i = sql.index(after: i)
                        break
                    }
                    i = sql.index(after: i)
                }
                continue
            }

            result.append(ch)
            i = sql.index(after: i)
        }
        return result
    }

    /// Split stripped SQL into word tokens, preserving punctuation as separate tokens.
    private static func tokenize(_ stripped: String) -> [String] {
        // Split on whitespace and common delimiters, keeping identifiers with dots (schema.table)
        var tokens: [String] = []
        var current = ""
        for ch in stripped {
            if ch.isWhitespace || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "(" || ch == ")" || ch == ";" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Helpers

    private static let keywordSet: Set<String> = Set([
        "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
        "TABLE", "VIEW", "INDEX", "PROCEDURE", "FUNCTION", "TRIGGER", "DATABASE",
        "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "CROSS", "ON", "AND", "OR", "NOT",
        "IN", "EXISTS", "BETWEEN", "LIKE", "IS", "NULL", "AS", "ORDER", "BY", "GROUP",
        "HAVING", "UNION", "ALL", "DISTINCT", "TOP", "INTO", "VALUES", "SET", "EXEC",
        "EXECUTE", "DECLARE", "BEGIN", "END", "IF", "ELSE", "WHILE", "RETURN", "CASE",
        "WHEN", "THEN", "WITH", "GO", "USE", "TRUNCATE", "GRANT", "REVOKE", "DENY",
        "ASC", "DESC", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT",
        "CHECK", "UNIQUE", "IDENTITY", "SCHEMA", "NOLOCK", "FULL", "OVER", "PARTITION",
        "OUTPUT", "OFFSET", "FETCH", "NEXT", "ROWS", "TRY", "CATCH", "THROW", "PRINT",
    ])

    private static func isKeyword(_ token: String) -> Bool {
        keywordSet.contains(token.uppercased())
    }

    /// System functions and expressions that don't require a FROM clause
    private static let systemExpressions: Set<String> = Set([
        "@@VERSION", "@@ROWCOUNT", "@@ERROR", "@@IDENTITY", "@@TRANCOUNT",
        "GETDATE()", "GETUTCDATE()", "NEWID()", "SUSER_SNAME()", "SYSTEM_USER",
        "CURRENT_TIMESTAMP", "CURRENT_USER", "SESSION_USER", "USER_NAME()",
        "DB_NAME()", "HOST_NAME()", "APP_NAME()", "SCHEMA_NAME()",
    ])

    private static func isSystemExpression(_ token: String) -> Bool {
        let upper = token.uppercased()
        return upper.hasPrefix("@@") || systemExpressions.contains(upper)
    }

    /// Find close matches using Levenshtein distance and prefix matching
    private static func fuzzyMatch(_ target: String, in candidates: [String], limit: Int) -> [String] {
        let targetLower = target.lowercased()
        var scored: [(String, Int)] = []

        for candidate in candidates {
            let candidateLower = candidate.lowercased()
            // Prefix match scores highest
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

    /// Simple Levenshtein distance
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
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
