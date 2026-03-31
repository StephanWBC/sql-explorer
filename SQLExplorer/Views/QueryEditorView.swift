import SwiftUI

struct QueryEditorView: View {
    @Binding var tab: QueryTab
    @EnvironmentObject var appState: AppState

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                // Query toolbar
                HStack(spacing: 8) {
                    Button {
                        Task { await executeQuery() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Run")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(tab.isExecuting || tab.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Execute query (⌘↵)")

                    if tab.isExecuting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                        Text("Executing...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let result = tab.result, !result.isError {
                        Text("\(result.rows.count) row(s)  ·  \(result.elapsedMs)ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(tab.database)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.bar)

                Divider()

                SQLTextEditor(text: $tab.sql)
                    .frame(minHeight: 150)
            }

            VStack(spacing: 0) {
                if tab.isExecuting {
                    ProgressView("Executing...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result = tab.result {
                    if result.isError {
                        ScrollView {
                            Text(result.errorMessage ?? "Unknown error")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.red)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if result.hasResults {
                        ResultsTableView(result: result)
                    } else {
                        VStack {
                            Text("Query executed successfully")
                                .foregroundStyle(.secondary)
                            Text("\(result.rowsAffected) row(s) affected  —  \(result.elapsedMs)ms")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("Execute a query to see results")
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    private func executeQuery() async {
        guard !tab.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        tab.isExecuting = true
        appState.statusMessage = "Executing on \(tab.database)..."

        do {
            let result = try await appState.connectionManager.executeQuery(
                tab.sql, connectionId: tab.connectionId)
            tab.result = result
            appState.statusMessage = "\(result.rows.count) row(s) in \(result.elapsedMs)ms"
        } catch {
            tab.result = QueryResult(errorMessage: error.localizedDescription)
            appState.statusMessage = "Error: \(error.localizedDescription)"
        }

        tab.isExecuting = false
    }
}

// MARK: - Pre-compiled Syntax Highlighting

/// All regex patterns compiled ONCE at app launch — not per keystroke
private enum SQLHighlighter {
    static let defaultColor = NSColor(red: 0.9, green: 0.93, blue: 0.95, alpha: 1)
    static let keywordColor = NSColor(red: 0.34, green: 0.65, blue: 1, alpha: 1)
    static let stringColor = NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1)
    static let commentColor = NSColor(red: 0.33, green: 0.55, blue: 0.33, alpha: 1)
    static let numberColor = NSColor(red: 0.7, green: 0.5, blue: 0.85, alpha: 1)

    // Single combined regex for ALL keywords (much faster than 47 separate regexes)
    static let keywordRegex: NSRegularExpression = {
        let keywords = [
            "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
            "TABLE", "VIEW", "INDEX", "PROCEDURE", "FUNCTION", "TRIGGER", "DATABASE",
            "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "CROSS", "ON", "AND", "OR", "NOT",
            "IN", "EXISTS", "BETWEEN", "LIKE", "IS", "NULL", "AS", "ORDER", "BY", "GROUP",
            "HAVING", "UNION", "ALL", "DISTINCT", "TOP", "INTO", "VALUES", "SET", "EXEC",
            "DECLARE", "BEGIN", "END", "IF", "ELSE", "WHILE", "RETURN", "CASE", "WHEN", "THEN",
            "WITH", "GO", "USE", "TRUNCATE", "GRANT", "REVOKE", "DENY", "ASC", "DESC",
            "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "CHECK",
            "UNIQUE", "IDENTITY", "SCHEMA", "NOLOCK", "COUNT", "SUM",
            "AVG", "MIN", "MAX", "ISNULL", "COALESCE", "CONVERT", "CAST",
        ]
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    static let stringRegex = try! NSRegularExpression(pattern: "'[^']*'")
    static let singleCommentRegex = try! NSRegularExpression(pattern: "--.*$", options: .anchorsMatchLines)
    static let multiCommentRegex = try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")
    static let numberRegex = try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")

    static func highlight(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()

        // Reset all to default
        storage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

        // Keywords (single regex with alternation — 1 pass instead of 47)
        for match in keywordRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
        }

        // Strings
        for match in stringRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: stringColor, range: match.range)
        }

        // Comments override everything
        for match in singleCommentRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
        }
        for match in multiCommentRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
        }

        // Numbers
        for match in numberRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: numberColor, range: match.range)
        }

        storage.endEditing()
    }
}

// MARK: - NSTextView Wrapper

struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator

        textView.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        textView.insertionPointColor = .white
        textView.textColor = SQLHighlighter.defaultColor
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]

        textView.string = text

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        private var highlightTimer: Timer?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string

            // Debounce: highlight 100ms after user stops typing
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak textView] _ in
                guard let tv = textView else { return }
                DispatchQueue.main.async {
                    SQLHighlighter.highlight(tv)
                }
            }
        }
    }
}
