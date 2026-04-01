import SwiftUI

struct ERDWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let schema = appState.erdSchema {
                switch schema.phase {
                case .pickingTables:
                    ERDTablePickerView(schema: schema, onGenerate: {
                        Task { await appState.generateERD() }
                    })
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let msg):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                        Text("Failed to load diagram")
                            .font(.headline)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    ERDDiagramView(schema: schema)
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

// MARK: - Table Picker (SSMS-style "Add Table" dialog)

struct ERDTablePickerView: View {
    @ObservedObject var schema: ERDSchema
    let onGenerate: () -> Void

    @State private var searchText = ""

    private var filteredTables: [ERDTableEntry] {
        if searchText.isEmpty {
            return schema.availableTables
        }
        let q = searchText.lowercased()
        return schema.availableTables.filter { $0.fullName.lowercased().contains(q) }
    }

    private var schemas: [String] {
        Array(Set(schema.availableTables.map(\.schema))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.connected.to.line.below")
                    .foregroundStyle(.blue)
                Text("New Diagram — \(schema.databaseName)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(schema.availableTables.count) tables available")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            HStack(spacing: 12) {
                // Left: table list with search
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        TextField("Filter tables...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Quick actions
                    HStack(spacing: 8) {
                        Button("Select All") {
                            for t in filteredTables {
                                schema.selectedTableNames.insert(t.fullName)
                            }
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Button("Deselect All") {
                            if searchText.isEmpty {
                                schema.selectedTableNames.removeAll()
                            } else {
                                for t in filteredTables {
                                    schema.selectedTableNames.remove(t.fullName)
                                }
                            }
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Spacer()

                        // Select by schema
                        Menu("By Schema") {
                            ForEach(schemas, id: \.self) { s in
                                Button(s) {
                                    for t in schema.availableTables where t.schema == s {
                                        schema.selectedTableNames.insert(t.fullName)
                                    }
                                }
                            }
                        }
                        .font(.system(size: 10))
                        .menuStyle(.borderlessButton)
                        .frame(width: 80)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                    Divider()

                    // Table list
                    List(filteredTables) { table in
                        HStack(spacing: 6) {
                            Image(systemName: schema.selectedTableNames.contains(table.fullName)
                                  ? "checkmark.square.fill" : "square")
                                .foregroundStyle(schema.selectedTableNames.contains(table.fullName) ? .blue : .secondary)
                                .font(.system(size: 13))

                            Image(systemName: "tablecells")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                                .frame(width: 14)

                            Text(table.schema)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(".")
                                .font(.system(size: 11))
                                .foregroundStyle(.quaternary)
                            Text(table.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if schema.selectedTableNames.contains(table.fullName) {
                                schema.selectedTableNames.remove(table.fullName)
                            } else {
                                schema.selectedTableNames.insert(table.fullName)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                    .listStyle(.plain)
                }

                // Right: selected summary + generate button
                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 36))
                        .foregroundStyle(schema.selectedTableNames.isEmpty ? Color.secondary.opacity(0.3) : Color.blue)

                    Text("\(schema.selectedTableNames.count) table(s) selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(schema.selectedTableNames.isEmpty ? .secondary : .primary)

                    if schema.selectedTableNames.count > 30 {
                        Text("Large diagrams may be slow")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }

                    Button {
                        onGenerate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Generate Diagram")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(schema.selectedTableNames.isEmpty ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(schema.selectedTableNames.isEmpty)

                    Spacer()
                }
                .frame(width: 200)
                .padding()
            }
        }
    }
}

// MARK: - Diagram View (toolbar + canvas)

struct ERDDiagramView: View {
    @ObservedObject var schema: ERDSchema
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .foregroundStyle(.blue)
                Text(schema.databaseName)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(schema.tables.count) tables")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                if !schema.relationships.isEmpty {
                    Text("\(schema.relationships.count) relationships")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    // Go back to table picker to add/remove tables
                    schema.phase = .pickingTables
                } label: {
                    Label("Edit Tables", systemImage: "tablecells.badge.ellipsis")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary)
                .cornerRadius(4)

                Button {
                    resetLayout()
                } label: {
                    Label("Reset Layout", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary)
                .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if schema.tables.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No tables found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ERDCanvasRepresentable(schema: schema)
            }
        }
    }

    private func resetLayout() {
        let cols = max(Int(ceil(sqrt(Double(schema.tables.count)))), 1)
        let spacing: CGFloat = 40
        let tableWidth: CGFloat = 240

        for (index, table) in schema.tables.enumerated() {
            let gridCol = index % cols
            let gridRow = index / cols
            table.position = CGPoint(
                x: CGFloat(gridCol) * (tableWidth + spacing) + 40,
                y: CGFloat(gridRow) * (200 + spacing) + 40
            )
        }
        schema.objectWillChange.send()
    }
}
