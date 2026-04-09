import SwiftUI

struct QueryEditorView: View {
    @Binding var tab: QueryTab
    @EnvironmentObject var appState: AppState
    @State private var showingSaveDialog = false
    @State private var saveName = ""
    @State private var showingHistory = false

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                // Query toolbar
                HStack(spacing: 6) {
                    // Play/Stop toggle
                    if tab.isExecuting {
                        Button {
                            appState.connectionManager.cancelQuery(connectionId: tab.connectionId)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 10))
                                Text("Cancel")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.red)
                            .foregroundStyle(.white)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel query (⌘.)")
                    } else {
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
                            .background(.green)
                            .foregroundStyle(.white)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .disabled(tab.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Execute query (⌘↵)")
                    }

                    // Save
                    Button {
                        saveName = tab.title
                        showingSaveDialog = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Save query (⌘S)")

                    // History
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Query history")

                    Spacer()

                    if let result = tab.result, !result.isError {
                        Text("\(result.rows.count) row(s)  ·  \(result.elapsedMs)ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    // Group alias badge (if in a group)
                    if !tab.groupAlias.isEmpty {
                        Text(tab.groupAlias)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }

                    // Server badge
                    if !tab.serverName.isEmpty {
                        Text(tab.serverName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }

                    // Database badge
                    Text(tab.database)
                        .font(.system(size: 10, weight: .semibold))
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
                        if let enriched = result.enrichedError {
                            ErrorPanelView(
                                enrichedError: enriched,
                                onSuggestionTap: { suggestion in
                                    handleSuggestion(suggestion)
                                },
                                onCopy: { text in
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                            )
                        } else {
                            ScrollView {
                                Text(result.errorMessage ?? "Unknown error")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
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
        .alert("Save Query", isPresented: $showingSaveDialog) {
            TextField("Query name", text: $saveName)
            Button("Save") {
                let name = saveName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                tab.title = name
                let saved = SavedQuery(
                    name: name, sql: tab.sql,
                    database: tab.database)
                appState.userDataStore.saveQuery(saved)
                tab.isSaved = true
                appState.statusMessage = "Query saved: \(name)"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this query a name to save it.")
        }
        .sheet(isPresented: $showingHistory) {
            QueryHistoryView(userDataStore: appState.userDataStore) { entry in
                tab.sql = entry.sql
            }
        }
    }

    private func executeQuery() async {
        let trimmed = tab.sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Pre-validate using schema data
        let issues = SQLPreValidator.validate(trimmed, schema: appState.schemaCache)
        let blockingErrors = issues.filter { $0.severity == .error }

        if !blockingErrors.isEmpty {
            let message = blockingErrors.first!.message
            let enriched = ErrorEnricher.enrich(
                sanitizedMessage: message,
                sql: trimmed,
                schema: appState.schemaCache,
                validationIssues: issues)
            tab.result = QueryResult(errorMessage: message, enrichedError: enriched, validationIssues: issues)
            appState.statusMessage = "Validation error"
            recordHistory()
            return
        }

        tab.isExecuting = true
        appState.statusMessage = "Executing on \(tab.database)..."

        do {
            var result = try await appState.connectionManager.executeQuery(
                tab.sql, connectionId: tab.connectionId)
            // Attach any pre-validation warnings to successful results
            result.validationIssues = issues.filter { $0.severity == .warning }
            tab.result = result
            appState.statusMessage = "\(result.rows.count) row(s) in \(result.elapsedMs)ms"
        } catch {
            let sanitized = ErrorSanitizer.sanitize(error.localizedDescription)
            let enriched = ErrorEnricher.enrich(
                sanitizedMessage: sanitized,
                sql: trimmed,
                schema: appState.schemaCache,
                validationIssues: issues)
            tab.result = QueryResult(errorMessage: sanitized, enrichedError: enriched, validationIssues: issues)
            appState.statusMessage = sanitized
        }

        recordHistory()
        tab.isExecuting = false
    }

    private func recordHistory() {
        let entry = QueryHistoryEntry(
            sql: tab.sql,
            database: tab.database,
            serverName: tab.serverName,
            rowCount: tab.result?.rows.count ?? 0,
            elapsedMs: tab.result?.elapsedMs ?? 0,
            wasError: tab.result?.isError ?? false
        )
        appState.userDataStore.addHistoryEntry(entry)
    }

    private func handleSuggestion(_ suggestion: ErrorSuggestion) {
        switch suggestion.action {
        case .insertText(let text):
            if !tab.sql.hasSuffix(" ") && !tab.sql.hasSuffix("\n") {
                tab.sql += " "
            }
            tab.sql += text
        case .replaceQuery(let text):
            tab.sql = text
        case .copyText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
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
        guard let storage = textView.textStorage, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let text = textView.string
        let fullLength = text.utf16.count
        guard fullLength > 0 else { return }

        // Determine visible range + buffer for context (handles partially visible multi-line comments)
        var highlightRange: NSRange
        if let scrollView = textView.enclosingScrollView {
            let visibleRect = scrollView.contentView.bounds
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            // Expand by 500 chars in each direction for context (multi-line comments, etc.)
            let bufferStart = max(0, charRange.location - 500)
            let bufferEnd = min(fullLength, charRange.location + charRange.length + 500)
            highlightRange = NSRange(location: bufferStart, length: bufferEnd - bufferStart)
        } else {
            highlightRange = NSRange(location: 0, length: fullLength)
        }

        storage.beginEditing()

        // Reset visible range to default
        storage.addAttribute(.foregroundColor, value: defaultColor, range: highlightRange)

        // Keywords (single regex with alternation — 1 pass instead of 47)
        for match in keywordRegex.matches(in: text, range: highlightRange) {
            storage.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
        }

        // Strings
        for match in stringRegex.matches(in: text, range: highlightRange) {
            storage.addAttribute(.foregroundColor, value: stringColor, range: match.range)
        }

        // Comments override everything
        for match in singleCommentRegex.matches(in: text, range: highlightRange) {
            storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
        }
        for match in multiCommentRegex.matches(in: text, range: highlightRange) {
            storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
        }

        // Numbers
        for match in numberRegex.matches(in: text, range: highlightRange) {
            storage.addAttribute(.foregroundColor, value: numberColor, range: match.range)
        }

        storage.endEditing()
    }
}

// MARK: - NSTextView Wrapper

struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Create custom text view with completion support
        let textView = CompletingTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticTextCompletionEnabled = true
        textView.delegate = context.coordinator

        textView.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        textView.insertionPointColor = .white
        textView.textColor = SQLHighlighter.defaultColor
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]

        textView.string = text

        // Auto-focus the text view so user can start typing immediately
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! CompletingTextView
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
        private var completionTimer: Timer?

        init(text: Binding<String>) {
            self.text = text
        }

        deinit {
            highlightTimer?.invalidate()
            completionTimer?.invalidate()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string

            // Debounce syntax highlighting (fires on main run loop — no async dispatch needed)
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak textView] _ in
                guard let tv = textView, tv.window != nil else { return }
                SQLHighlighter.highlight(tv)
            }

            // Debounce completion — only trigger after 400ms pause, and only if 3+ chars typed
            completionTimer?.invalidate()
            completionTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak textView] _ in
                guard let tv = textView, tv.window != nil else { return }
                let range = tv.selectedRange()
                guard range.length == 0, range.location > 0 else { return }
                let str = tv.string as NSString
                let strLen = str.length
                guard range.location <= strLen else { return }
                var start = range.location
                while start > 0 {
                    let ch = str.character(at: start - 1)
                    let c = Character(UnicodeScalar(ch)!)
                    if c.isLetter || c.isNumber || c == "_" || c == "." { start -= 1 }
                    else { break }
                }
                if range.location - start >= 3 {
                    MainActor.assumeIsolated {
                        tv.complete(nil)
                    }
                }
            }
        }

        // NSTextView completion delegate — returns matching suggestions
        func textView(_ textView: NSTextView, completions words: [String],
                      forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {

            guard charRange.length > 0 else { return [] }
            let partial = (textView.string as NSString).substring(with: charRange).lowercased()
            guard partial.count >= 2 else { return [] }

            let allCompletions = CompletionProvider.completions
            guard !allCompletions.isEmpty else { return [] }

            // Prefix matches first (most relevant), then contains
            var results: [String] = []
            var seen = Set<String>()

            for item in allCompletions {
                if item.lowercased().hasPrefix(partial) && seen.insert(item).inserted {
                    results.append(item)
                }
                if results.count >= 15 { break }
            }

            if results.count < 15 {
                for item in allCompletions {
                    if !item.lowercased().hasPrefix(partial) && item.lowercased().contains(partial) && seen.insert(item).inserted {
                        results.append(item)
                    }
                    if results.count >= 15 { break }
                }
            }

            index?.pointee = -1  // No pre-selection
            return results
        }
    }
}

// MARK: - NSTextView subclass with custom word boundary (includes dots for schema.table)

class CompletingTextView: NSTextView {
    // Custom word range — includes dots for schema.table (e.g. "BLMS.Lead")
    override var rangeForUserCompletion: NSRange {
        let cursorLocation = selectedRange().location
        let text = string as NSString
        var start = cursorLocation

        while start > 0 {
            let ch = text.character(at: start - 1)
            let c = Character(UnicodeScalar(ch)!)
            if c.isLetter || c.isNumber || c == "_" || c == "." { start -= 1 }
            else { break }
        }

        return NSRange(location: start, length: cursorLocation - start)
    }

    // Ctrl+Space to manually trigger completion (like SSMS)
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == " " {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }
}
