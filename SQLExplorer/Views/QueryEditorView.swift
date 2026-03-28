import SwiftUI

struct QueryEditorView: View {
    @Binding var tab: QueryTab
    @EnvironmentObject var appState: AppState

    var body: some View {
        VSplitView {
            // SQL Editor
            VStack(spacing: 0) {
                SQLTextEditor(text: $tab.sql)
                    .frame(minHeight: 150)
            }

            // Results area
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
}

/// Simple NSTextView-based SQL editor with monospace font
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

        // Dark theme colors
        textView.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        textView.insertionPointColor = .white
        textView.textColor = NSColor(red: 0.9, green: 0.93, blue: 0.95, alpha: 1)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor
        ]

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

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            highlightSQL(textView)
        }

        /// Basic T-SQL syntax highlighting
        private func highlightSQL(_ textView: NSTextView) {
            let text = textView.string
            let fullRange = NSRange(location: 0, length: text.utf16.count)

            // Reset to default color
            let defaultColor = NSColor(red: 0.9, green: 0.93, blue: 0.95, alpha: 1)
            textView.textStorage?.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

            // Keywords — blue
            let keywords = ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
                           "TABLE", "VIEW", "INDEX", "PROCEDURE", "FUNCTION", "TRIGGER", "DATABASE",
                           "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "CROSS", "ON", "AND", "OR", "NOT",
                           "IN", "EXISTS", "BETWEEN", "LIKE", "IS", "NULL", "AS", "ORDER", "BY", "GROUP",
                           "HAVING", "UNION", "ALL", "DISTINCT", "TOP", "INTO", "VALUES", "SET", "EXEC",
                           "DECLARE", "BEGIN", "END", "IF", "ELSE", "WHILE", "RETURN", "CASE", "WHEN", "THEN",
                           "WITH", "GO", "USE", "TRUNCATE", "GRANT", "REVOKE", "DENY", "ASC", "DESC",
                           "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "CHECK",
                           "UNIQUE", "IDENTITY", "NOT", "NULL", "SCHEMA", "NOLOCK", "COUNT", "SUM",
                           "AVG", "MIN", "MAX", "ISNULL", "COALESCE", "CONVERT", "CAST"]
            let keywordColor = NSColor(red: 0.34, green: 0.65, blue: 1, alpha: 1)  // Blue

            for keyword in keywords {
                let pattern = "\\b\(keyword)\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: fullRange)
                    for match in matches {
                        textView.textStorage?.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
                    }
                }
            }

            // Strings — orange
            let stringColor = NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1)
            if let regex = try? NSRegularExpression(pattern: "'[^']*'", options: []) {
                for match in regex.matches(in: text, range: fullRange) {
                    textView.textStorage?.addAttribute(.foregroundColor, value: stringColor, range: match.range)
                }
            }

            // Comments — green
            let commentColor = NSColor(red: 0.33, green: 0.55, blue: 0.33, alpha: 1)
            // Single-line comments
            if let regex = try? NSRegularExpression(pattern: "--.*$", options: .anchorsMatchLines) {
                for match in regex.matches(in: text, range: fullRange) {
                    textView.textStorage?.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                }
            }
            // Multi-line comments
            if let regex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/", options: []) {
                for match in regex.matches(in: text, range: fullRange) {
                    textView.textStorage?.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                }
            }

            // Numbers — purple
            let numberColor = NSColor(red: 0.7, green: 0.5, blue: 0.85, alpha: 1)
            if let regex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b", options: []) {
                for match in regex.matches(in: text, range: fullRange) {
                    textView.textStorage?.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                }
            }
        }
    }
}
