import SwiftUI

struct ErrorPanelView: View {
    let enrichedError: EnrichedError
    let onSuggestionTap: (ErrorSuggestion) -> Void
    let onCopy: (String) -> Void

    @State private var showCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Error header
                errorHeader

                // Suggestion chips
                if !enrichedError.suggestions.isEmpty {
                    suggestionSection
                }

                // Validation warnings
                let warnings = enrichedError.validationIssues.filter { $0.severity == .warning }
                if !warnings.isEmpty {
                    warningSection(warnings)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Error Header

    private var errorHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            // Category icon
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            // Message
            VStack(alignment: .leading, spacing: 4) {
                Text(categoryLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .textCase(.uppercase)

                Text(enrichedError.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            Spacer()

            // Copy button
            Button {
                onCopy(enrichedError.message)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showCopied = false
                }
            } label: {
                if showCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Copy error message")
        }
        .padding(12)
        .background(iconColor.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Suggestions

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Did you mean?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            FlowLayoutView(items: enrichedError.suggestions) { suggestion in
                Button {
                    onSuggestionTap(suggestion)
                } label: {
                    Text(suggestion.text)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .help(actionDescription(suggestion))
            }
        }
    }

    // MARK: - Warnings

    private func warningSection(_ warnings: [SQLValidationIssue]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, issue in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(issue.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let suggestion = issue.suggestion {
                        Text(suggestion)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var iconName: String {
        switch enrichedError.category {
        case .syntax:         return "exclamationmark.triangle.fill"
        case .objectNotFound: return "magnifyingglass"
        case .permission:     return "lock.fill"
        case .connection:     return "wifi.exclamationmark"
        case .execution:      return "xmark.circle.fill"
        case .validation:     return "checkmark.shield.fill"
        case .unknown:        return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch enrichedError.category {
        case .syntax:         return .yellow
        case .objectNotFound: return .orange
        case .permission:     return .red
        case .connection:     return .red
        case .execution:      return .red
        case .validation:     return .blue
        case .unknown:        return .red
        }
    }

    private var categoryLabel: String {
        switch enrichedError.category {
        case .syntax:         return "Syntax Error"
        case .objectNotFound: return "Object Not Found"
        case .permission:     return "Permission Denied"
        case .connection:     return "Connection Error"
        case .execution:      return "Execution Error"
        case .validation:     return "Validation"
        case .unknown:        return "Error"
        }
    }

    private func actionDescription(_ suggestion: ErrorSuggestion) -> String {
        switch suggestion.action {
        case .insertText(let text): return "Insert: \(text)"
        case .replaceQuery(let text): return "Replace with: \(text)"
        case .copyText(let text): return "Copy: \(text)"
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout for suggestion chips)

struct FlowLayoutView<Item, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                content(item)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geometry.size.width {
                            width = 0
                            height -= d.height + 4
                        }
                        let result = width
                        if index == items.count - 1 {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if index == items.count - 1 {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geometry -> Color in
            DispatchQueue.main.async {
                binding.wrappedValue = geometry.frame(in: .local).size.height
            }
            return Color.clear
        }
    }
}
