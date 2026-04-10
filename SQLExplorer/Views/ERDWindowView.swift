import SwiftUI

struct ERDWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSidebar = true
    @State private var searchText = ""

    var body: some View {
        Group {
            if let schema = appState.erdSchema {
                HSplitView {
                    // Sidebar: table list
                    if showSidebar {
                        ERDSidebarView(
                            schema: schema,
                            searchText: $searchText,
                            onAddTable: { entry in
                                Task { await appState.addTableToERD(entry) }
                            },
                            onRemoveTable: { table in
                                Task { await appState.removeTableFromERD(table) }
                            }
                        )
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
                    }

                    // Canvas — separate view to observe schema changes
                    ERDCanvasAreaView(
                        schema: schema,
                        showSidebar: $showSidebar
                    )
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("Open a Database Diagram from the context menu")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Canvas Area (observes schema for live updates)

struct ERDCanvasAreaView: View {
    @ObservedObject var schema: ERDSchema
    @Binding var showSidebar: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(showSidebar ? "Hide sidebar" : "Show sidebar")

                Image(systemName: "rectangle.connected.to.line.below")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))

                Text(schema.databaseName)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                if schema.isAddingTable {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }

                Text("\(schema.tables.count) tables")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                if !schema.relationships.isEmpty {
                    Text("\(schema.relationships.count) FKs")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    resetLayout()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Reset layout")
                .disabled(schema.tables.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Canvas area
            if schema.tables.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 40))
                        .foregroundStyle(.quaternary)
                    Text("Add tables from the sidebar")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Double-click or use the + button to add tables to the diagram")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ERDCanvasRepresentable(schema: schema)
            }
        }
    }

    private func resetLayout() {
        let cols = max(Int(ceil(sqrt(Double(schema.tables.count)))), 1)
        for (i, table) in schema.tables.enumerated() {
            table.position = CGPoint(
                x: CGFloat(i % cols) * 280 + 40,
                y: CGFloat(i / cols) * 240 + 40
            )
        }
        schema.objectWillChange.send()
    }
}

// MARK: - Sidebar

struct ERDSidebarView: View {
    @ObservedObject var schema: ERDSchema
    @Binding var searchText: String
    let onAddTable: (ERDTableEntry) -> Void
    let onRemoveTable: (ERDTable) -> Void

    private var filteredTables: [ERDTableEntry] {
        let available = schema.availableTables
        if searchText.isEmpty { return available }
        let q = searchText.lowercased()
        return available.filter { $0.fullName.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10))
                TextField("Filter tables...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .cornerRadius(5)
            .padding(8)

            Divider()

            // Table list
            if schema.isLoadingTableList {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading tables...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Tables on canvas
                        if !schema.tables.isEmpty {
                            sectionHeader("ON DIAGRAM (\(schema.tables.count))", color: .green)
                            ForEach(schema.tables) { table in
                                canvasTableRow(table)
                            }
                        }

                        // Available tables
                        sectionHeader("AVAILABLE (\(filteredTables.count))", color: .secondary)
                        ForEach(filteredTables) { entry in
                            availableTableRow(entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .tracking(0.5)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func canvasTableRow(_ table: ERDTable) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 10))
            Image(systemName: "tablecells")
                .foregroundStyle(.green)
                .font(.system(size: 9))
            Text(table.fullName)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Button {
                onRemoveTable(table)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.7))
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func availableTableRow(_ entry: ERDTableEntry) -> some View {
        let onCanvas = schema.tablesOnCanvas.contains(entry.fullName)
        HStack(spacing: 5) {
            Image(systemName: "tablecells")
                .foregroundStyle(onCanvas ? Color.secondary : Color.green)
                .font(.system(size: 9))
            Text(entry.schema)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(".\(entry.name)")
                .font(.system(size: 11, weight: onCanvas ? .regular : .medium))
                .foregroundStyle(onCanvas ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer()
            if !onCanvas {
                Button {
                    onAddTable(entry)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !onCanvas { onAddTable(entry) }
        }
    }
}
