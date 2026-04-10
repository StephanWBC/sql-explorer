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
    @EnvironmentObject var appState: AppState
    @ObservedObject var schema: ERDSchema
    @Binding var showSidebar: Bool
    @State private var showSaveDialog = false
    @State private var saveName = ""

    private var diagramsForDatabase: [SavedDiagram] {
        appState.userDataStore.savedDiagrams.filter { $0.databaseName == schema.databaseName }
    }

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

                if !schema.savedDiagramName.isEmpty {
                    Text("— \(schema.savedDiagramName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

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

                // Save button
                Button {
                    if schema.savedDiagramId != nil {
                        // Quick-save to existing diagram
                        appState.saveDiagram(name: schema.savedDiagramName)
                    } else {
                        saveName = schema.databaseName + " Diagram"
                        showSaveDialog = true
                    }
                } label: {
                    toolbarButton(icon: "square.and.arrow.down", label: "Save")
                }
                .buttonStyle(.plain)
                .help(schema.savedDiagramId != nil ? "Save diagram (Cmd+S)" : "Save diagram as...")
                .disabled(schema.tables.isEmpty)

                // Load menu
                Menu {
                    if diagramsForDatabase.isEmpty {
                        Text("No saved diagrams")
                    } else {
                        ForEach(diagramsForDatabase) { diagram in
                            Button {
                                Task { await appState.loadDiagram(diagram) }
                            } label: {
                                Label(diagram.name, systemImage: "rectangle.connected.to.line.below")
                            }
                        }
                        Divider()
                        Menu("Delete...") {
                            ForEach(diagramsForDatabase) { diagram in
                                Button(role: .destructive) {
                                    appState.deleteDiagram(diagram.id)
                                } label: {
                                    Label(diagram.name, systemImage: "trash")
                                }
                            }
                        }
                    }
                } label: {
                    toolbarButton(icon: "folder", label: "Open")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 70)
                .help("Load saved diagram")

                Button {
                    autoArrangeLayout()
                } label: {
                    toolbarButton(icon: "wand.and.stars", label: "Arrange")
                }
                .buttonStyle(.plain)
                .help("Auto arrange tables based on relationships")
                .disabled(schema.tables.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
            .alert("Save Diagram", isPresented: $showSaveDialog) {
                TextField("Diagram name", text: $saveName)
                Button("Save") {
                    guard !saveName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    appState.saveDiagram(name: saveName)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name for this diagram")
            }

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

    // MARK: - Hierarchical auto-arrange layout

    private func autoArrangeLayout() {
        let tables = schema.tables
        guard !tables.isEmpty else { return }

        let tableW = ERDCanvasNSView.tableWidth     // 220
        let headerH = ERDCanvasNSView.headerHeight   // 28
        let rowH = ERDCanvasNSView.rowHeight          // 20
        let hGap: CGFloat = 80
        let vGap: CGFloat = 60
        let margin: CGFloat = 40

        if tables.count == 1 {
            tables[0].position = CGPoint(x: margin, y: margin)
            schema.objectWillChange.send()
            return
        }

        func tableHeight(_ t: ERDTable) -> CGFloat {
            headerH + CGFloat(t.columns.count) * rowH + 4
        }

        let allNames = Set(tables.map(\.fullName))

        // Build directed graph from FK relationships
        // fromTable (has FK column) references toTable (lookup/parent table)
        // Hierarchy: toTable is ABOVE, fromTable is BELOW
        var referencedBy: [String: Set<String>] = [:]  // table → tables that have FKs to it (children)
        var referencesTo: [String: Set<String>] = [:]   // table → tables it points FK to (parents)

        for name in allNames {
            referencedBy[name] = []
            referencesTo[name] = []
        }

        var seenEdges = Set<String>()
        for rel in schema.relationships {
            guard rel.fromTable != rel.toTable else { continue }
            let key = "\(rel.fromTable)→\(rel.toTable)"
            guard !seenEdges.contains(key) else { continue }
            seenEdges.insert(key)
            referencedBy[rel.toTable]?.insert(rel.fromTable)
            referencesTo[rel.fromTable]?.insert(rel.toTable)
        }

        // --- Layer assignment (longest-path from roots) ---
        // Roots = tables with no outgoing FK references (pure lookup tables)
        var roots = allNames.filter { (referencesTo[$0] ?? []).isEmpty }
        if roots.isEmpty {
            // All tables reference something (cycle): pick the most-referenced table as root
            roots = [allNames.max(by: {
                (referencedBy[$0] ?? []).count < (referencedBy[$1] ?? []).count
            }) ?? tables[0].fullName]
        }

        var layerOf: [String: Int] = [:]
        for root in roots { layerOf[root] = 0 }

        // BFS with longest-path update
        var queue = roots.map { ($0, 0) }
        var qi = 0
        while qi < queue.count {
            let (current, currentLayer) = queue[qi]
            qi += 1
            for child in referencedBy[current] ?? [] {
                let newLayer = currentLayer + 1
                if let existing = layerOf[child] {
                    if newLayer > existing { layerOf[child] = newLayer }
                } else {
                    layerOf[child] = newLayer
                    queue.append((child, newLayer))
                }
            }
        }

        // Assign unvisited tables (disconnected) to layer 0
        for name in allNames where layerOf[name] == nil {
            layerOf[name] = 0
        }

        // --- Layer compaction: pull tables down closer to their children ---
        // This prevents long edges (e.g. Flag at layer 0 when its only child LeadFlag is at layer 2)
        // Process from top layers down; move each table to just above its closest child
        let maxLayer = layerOf.values.max() ?? 0
        for targetLayer in 0..<maxLayer {
            for name in allNames where layerOf[name] == targetLayer {
                let children = referencedBy[name] ?? []
                guard !children.isEmpty else { continue }
                let minChildLayer = children.compactMap { layerOf[$0] }.min() ?? (targetLayer + 1)
                let parents = referencesTo[name] ?? []
                let maxParentLayer = parents.compactMap { layerOf[$0] }.max() ?? -1
                // Pull down: sit just above closest child, but stay below all parents
                let ideal = minChildLayer - 1
                let constrained = max(ideal, maxParentLayer + 1)
                if constrained > targetLayer {
                    layerOf[name] = constrained
                }
            }
        }

        // --- Renumber layers to remove gaps ---
        let usedLayers = Set(layerOf.values).sorted()
        let layerRemap = Dictionary(uniqueKeysWithValues: usedLayers.enumerated().map { ($1, $0) })
        for name in allNames {
            layerOf[name] = layerRemap[layerOf[name] ?? 0] ?? 0
        }

        // --- Group tables by layer ---
        var layerGroups: [Int: [ERDTable]] = [:]
        for table in tables {
            let l = layerOf[table.fullName] ?? 0
            layerGroups[l, default: []].append(table)
        }
        var sortedLayers = layerGroups.keys.sorted()

        // --- Order within layers (multi-pass barycenter crossing minimization) ---
        // Seed: sort first layer by degree (most-connected first) then alphabetical
        layerGroups[sortedLayers[0]]?.sort(by: { a, b in
            let aDeg = (referencedBy[a.fullName] ?? []).count + (referencesTo[a.fullName] ?? []).count
            let bDeg = (referencedBy[b.fullName] ?? []).count + (referencesTo[b.fullName] ?? []).count
            if aDeg != bDeg { return aDeg > bDeg }
            return a.fullName < b.fullName
        })

        // Build positional index
        var posIndex: [String: CGFloat] = [:]
        func rebuildIndex() {
            for layerKey in sortedLayers {
                for (i, t) in (layerGroups[layerKey] ?? []).enumerated() {
                    posIndex[t.fullName] = CGFloat(i)
                }
            }
        }
        rebuildIndex()

        // Run 4 passes (alternate down/up sweeps) for better convergence
        for pass in 0..<4 {
            let layerOrder = pass % 2 == 0
                ? Array(sortedLayers.dropFirst())          // top-down
                : Array(sortedLayers.dropLast().reversed()) // bottom-up

            for layerKey in layerOrder {
                layerGroups[layerKey]?.sort(by: { a, b in
                    // Barycenter: average position of ALL connected tables (parents + children)
                    let aConns = ((referencesTo[a.fullName] ?? []) as Set)
                        .union(referencedBy[a.fullName] ?? [])
                        .compactMap { posIndex[$0] }
                    let bConns = ((referencesTo[b.fullName] ?? []) as Set)
                        .union(referencedBy[b.fullName] ?? [])
                        .compactMap { posIndex[$0] }
                    let aCenter = aConns.isEmpty ? CGFloat(999)
                        : aConns.reduce(0, +) / CGFloat(aConns.count)
                    let bCenter = bConns.isEmpty ? CGFloat(999)
                        : bConns.reduce(0, +) / CGFloat(bConns.count)
                    if aCenter != bCenter { return aCenter < bCenter }
                    return a.fullName < b.fullName
                })
            }
            rebuildIndex()
        }

        // --- Assign grid-aligned positions ---
        sortedLayers = layerGroups.keys.sorted()
        let maxCount = layerGroups.values.map(\.count).max() ?? 1
        let totalWidth = CGFloat(maxCount) * (tableW + hGap) - hGap

        var yPos = margin
        for layerKey in sortedLayers {
            let layerTables = layerGroups[layerKey] ?? []
            let layerWidth = CGFloat(layerTables.count) * (tableW + hGap) - hGap
            let xStart = margin + (totalWidth - layerWidth) / 2   // Center layer horizontally

            var maxH: CGFloat = 0
            for (i, table) in layerTables.enumerated() {
                table.position = CGPoint(
                    x: xStart + CGFloat(i) * (tableW + hGap),
                    y: yPos
                )
                maxH = max(maxH, tableHeight(table))
            }

            yPos += maxH + vGap
        }

        schema.objectWillChange.send()
    }

    @ViewBuilder
    private func toolbarButton(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
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
