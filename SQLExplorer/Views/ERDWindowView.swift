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
                    autoArrangeLayout()
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Auto arrange")
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

    /// Force-directed auto-arrange: connected tables cluster together, others spread apart
    private func autoArrangeLayout() {
        let tables = schema.tables
        guard !tables.isEmpty else { return }

        if tables.count == 1 {
            tables[0].position = CGPoint(x: 40, y: 40)
            schema.objectWillChange.send()
            return
        }

        let tableW = ERDCanvasNSView.tableWidth
        let rowH = ERDCanvasNSView.rowHeight
        let headerH = ERDCanvasNSView.headerHeight

        // Build adjacency lookup (bidirectional)
        var adj: [String: Set<String>] = [:]
        for rel in schema.relationships {
            adj[rel.fromTable, default: []].insert(rel.toTable)
            adj[rel.toTable, default: []].insert(rel.fromTable)
        }

        // Seed positions: spread tables in a circle so the simulation starts untangled
        let cx: CGFloat = CGFloat(tables.count) * 140
        let cy: CGFloat = CGFloat(tables.count) * 120
        let radius: CGFloat = CGFloat(tables.count) * 100
        for (i, table) in tables.enumerated() {
            let angle = (2.0 * .pi / CGFloat(tables.count)) * CGFloat(i)
            table.position = CGPoint(
                x: cx + cos(angle) * radius,
                y: cy + sin(angle) * radius
            )
        }

        // Force-directed simulation parameters
        let iterations = 150
        let repulsion: CGFloat = 80000
        let attraction: CGFloat = 0.005
        let idealEdge: CGFloat = 350
        var damping: CGFloat = 0.85
        let maxSpeed: CGFloat = 40

        var velocities: [UUID: CGPoint] = [:]
        for table in tables { velocities[table.id] = .zero }

        for _ in 0..<iterations {
            var forces: [UUID: CGPoint] = [:]
            for table in tables { forces[table.id] = .zero }

            // Repulsion between every pair (considers actual table size for overlap avoidance)
            for i in 0..<tables.count {
                for j in (i + 1)..<tables.count {
                    let a = tables[i], b = tables[j]
                    let ah = headerH + CGFloat(a.columns.count) * rowH + 4
                    let bh = headerH + CGFloat(b.columns.count) * rowH + 4
                    let dx = a.position.x - b.position.x
                    let dy = a.position.y - b.position.y
                    let dist = max(sqrt(dx * dx + dy * dy), 1)
                    // Stronger repulsion when tables would overlap
                    let minSep = max(tableW + 40, (ah + bh) / 2 + 40)
                    let boost: CGFloat = dist < minSep ? 3.0 : 1.0
                    let force = repulsion * boost / (dist * dist)
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force
                    forces[a.id]!.x += fx;  forces[a.id]!.y += fy
                    forces[b.id]!.x -= fx;  forces[b.id]!.y -= fy
                }
            }

            // Attraction along FK edges
            for rel in schema.relationships {
                guard let a = tables.first(where: { $0.fullName == rel.fromTable }),
                      let b = tables.first(where: { $0.fullName == rel.toTable }) else { continue }
                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let force = attraction * (dist - idealEdge)
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force
                forces[a.id]!.x += fx;  forces[a.id]!.y += fy
                forces[b.id]!.x -= fx;  forces[b.id]!.y -= fy
            }

            // Apply forces with velocity damping
            for table in tables {
                var v = velocities[table.id]!
                v.x = (v.x + forces[table.id]!.x) * damping
                v.y = (v.y + forces[table.id]!.y) * damping
                let speed = sqrt(v.x * v.x + v.y * v.y)
                if speed > maxSpeed {
                    v.x = v.x / speed * maxSpeed
                    v.y = v.y / speed * maxSpeed
                }
                velocities[table.id] = v
                table.position.x += v.x
                table.position.y += v.y
            }

            damping *= 0.99 // Gradual cooldown
        }

        // Normalize: shift so top-left table starts at a comfortable margin
        let minX = tables.map(\.position.x).min() ?? 0
        let minY = tables.map(\.position.y).min() ?? 0
        for table in tables {
            table.position.x = table.position.x - minX + 40
            table.position.y = table.position.y - minY + 40
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

    /// Related tables grouped by which canvas table they connect to, filtered by search
    private var groupedRelatedTables: [(canvasTable: String, related: [ERDRelatedTable])] {
        let onCanvas = schema.tablesOnCanvas
        let filtered = schema.relatedTables.filter { rel in
            // Exclude tables already on canvas
            guard !onCanvas.contains(rel.fullName) else { return false }
            // Apply search filter
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return rel.fullName.lowercased().contains(q)
            }
            return true
        }
        let grouped = Dictionary(grouping: filtered, by: \.relatedToTable)
        return grouped.sorted(by: { $0.key < $1.key })
            .map { (canvasTable: $0.key, related: $0.value.sorted(by: { $0.fullName < $1.fullName })) }
    }

    private var totalRelatedCount: Int {
        groupedRelatedTables.reduce(0) { $0 + $1.related.count }
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

                        // Related tables (FK-connected but not on canvas)
                        if totalRelatedCount > 0 {
                            sectionHeader("RELATED (\(totalRelatedCount))", color: .orange)
                            ForEach(groupedRelatedTables, id: \.canvasTable) { group in
                                relatedGroupHeader(group.canvasTable)
                                ForEach(group.related) { rel in
                                    relatedTableRow(rel)
                                }
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
    private func relatedGroupHeader(_ canvasTable: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .foregroundStyle(.orange.opacity(0.6))
                .font(.system(size: 8))
            Text("via \(canvasTable)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.orange.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func relatedTableRow(_ rel: ERDRelatedTable) -> some View {
        let onCanvas = schema.tablesOnCanvas.contains(rel.fullName)
        HStack(spacing: 4) {
            Image(systemName: rel.direction == .outgoing ? "arrow.right" : "arrow.left")
                .foregroundStyle(.orange.opacity(0.8))
                .font(.system(size: 8, weight: .semibold))
            Image(systemName: "tablecells")
                .foregroundStyle(.orange.opacity(0.7))
                .font(.system(size: 9))
            Text(rel.fullName)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            if !onCanvas {
                Button {
                    onAddTable(ERDTableEntry(schema: rel.schema, name: rel.name))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !onCanvas { onAddTable(ERDTableEntry(schema: rel.schema, name: rel.name)) }
        }
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
