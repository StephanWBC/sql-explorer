import SwiftUI

struct QueryHistoryView: View {
    @ObservedObject var userDataStore: UserDataStore
    @Environment(\.dismiss) var dismiss
    let onSelect: (QueryHistoryEntry) -> Void

    @State private var searchText = ""
    @State private var showClearConfirmation = false

    private var filteredHistory: [QueryHistoryEntry] {
        if searchText.isEmpty { return userDataStore.queryHistory }
        return userDataStore.queryHistory.filter {
            $0.sql.localizedCaseInsensitiveContains(searchText) ||
            $0.database.localizedCaseInsensitiveContains(searchText) ||
            $0.serverName.localizedCaseInsensitiveContains(searchText)
        }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Query History")
                    .font(.headline)
                Spacer()
                Button("Clear All", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(userDataStore.queryHistory.isEmpty)
                Button("Done") { dismiss() }
            }
            .padding()

            // Search
            TextField("Search queries...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty ? "No query history yet" : "No matching queries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredHistory) { entry in
                    QueryHistoryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(entry)
                            dismiss()
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 600, height: 500)
        .confirmationDialog("Clear History", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { userDataStore.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all query history entries? This cannot be undone.")
        }
    }
}

private struct QueryHistoryRow: View {
    let entry: QueryHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // SQL preview (first 2 lines, truncated)
            Text(entry.sql.components(separatedBy: .newlines).prefix(2).joined(separator: " "))
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(entry.wasError ? .red : .primary)

            HStack(spacing: 8) {
                Label(entry.database, systemImage: "cylinder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if !entry.serverName.isEmpty {
                    Text(entry.serverName)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if entry.wasError {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                } else {
                    Text("\(entry.rowCount) row(s)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(entry.elapsedMs)ms")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Text(QueryHistoryView.timeFormatter.string(from: entry.executedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
