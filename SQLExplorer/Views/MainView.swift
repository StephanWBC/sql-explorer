import SwiftUI

enum SidebarTab: String, CaseIterable {
    case explorer = "Explorer"
    case favorites = "Favorites"
    case groups = "Groups"

    var icon: String {
        switch self {
        case .explorer: return "cylinder.split.1x2"
        case .favorites: return "star.fill"
        case .groups: return "folder.fill"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var explorerWidth: CGFloat = 280
    @State private var selectedSidebarTab: SidebarTab = .explorer
    @State private var expandedNodes: Set<UUID> = []
    @State private var selectedSchemas: Set<String> = []
    @State private var explorerSearchText: String = ""

    var body: some View {
        HSplitView {
            // Left: Sidebar
            VStack(spacing: 0) {
                // Account banner
                AccountBannerView(authService: appState.authService)

                Divider()

                // Sidebar tab picker
                Picker("", selection: $selectedSidebarTab) {
                    ForEach(SidebarTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                // Schema filter (only on Explorer tab when schemas exist)
                if selectedSidebarTab == .explorer && availableSchemas.count > 1 {
                    VStack(spacing: 0) {
                        // Search bar
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                            TextField("Search tables, views...", text: $explorerSearchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                            if !explorerSearchText.isEmpty {
                                Button { explorerSearchText = "" } label: {
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
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 4)

                        // Schema chips
                        HStack {
                            Text("SCHEMAS")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(availableSchemas, id: \.self) { s in
                                    let isSelected = selectedSchemas.contains(s)
                                    Button {
                                        if isSelected { selectedSchemas.remove(s) }
                                        else { selectedSchemas.insert(s) }
                                    } label: {
                                        Text(s)
                                            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                if !selectedSchemas.isEmpty {
                                    Button { selectedSchemas.removeAll() } label: {
                                        Text("Clear")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .padding(.bottom, 4)

                        Divider()
                    }
                }

                // Tab content
                switch selectedSidebarTab {
                case .explorer:
                    explorerContent
                case .favorites:
                    FavoritesView(userDataStore: appState.userDataStore, selectedSidebarTab: $selectedSidebarTab)
                        .environmentObject(appState)
                case .groups:
                    GroupsView(userDataStore: appState.userDataStore, selectedSidebarTab: $selectedSidebarTab)
                        .environmentObject(appState)
                }
            }
            .frame(minWidth: 220, idealWidth: explorerWidth, maxWidth: 450)

            // Right: Query editor area
            VStack(spacing: 0) {
                if appState.queryTabs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("SQL Explorer")
                            .font(.title)
                            .fontWeight(.light)
                            .foregroundStyle(.secondary)
                        Text("Double-click a database to connect, then open a query tab.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 16) {
                            Text("⌘T new query")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Text("⌘↵ execute")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Custom tab bar
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(appState.queryTabs) { tab in
                                    QueryTabButton(
                                        tab: tab,
                                        isSelected: appState.selectedTabId == tab.id,
                                        onSelect: { appState.selectedTabId = tab.id },
                                        onClose: { appState.closeTab(tab.id) }
                                    )
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(height: 30)
                        .background(.bar)

                        Divider()

                        // Content area — show selected tab
                        if let idx = appState.queryTabs.firstIndex(where: { $0.id == appState.selectedTabId }) {
                            QueryEditorView(tab: $appState.queryTabs[idx])
                        }
                    }
                }
            }
        }
        .toolbar(.hidden)
        .onAppear {
            if !appState.authService.databases.isEmpty && appState.explorerNodes.isEmpty {
                appState.buildExplorerFromDatabases(appState.authService.databases)
            }
        }
        .onReceive(appState.authService.$databases) { newDatabases in
            guard !newDatabases.isEmpty else { return }
            appState.buildExplorerFromDatabases(newDatabases)
        }
        .onReceive(appState.authService.$serverToSubscription) { map in
            // Cross-subscription server map just resolved — rewrite stale member
            // subscriptionIds so the cross-sub pill renders correctly. (Bug fix:
            // members were previously tagged with whatever sub was selected at
            // add-time, not the server's actual sub.)
            appState.userDataStore.normalizeAzureSubscriptions(using: map)
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
                .environmentObject(appState)
        }
    }

    // MARK: - Explorer Content

    @ViewBuilder
    private func connectedDbLabel(_ db: DatabaseObject) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(db.name)
                    .font(.system(size: 12, weight: .medium))
                if let fqdn = db.serverFqdn {
                    Text(fqdn.replacingOccurrences(of: ".database.windows.net", with: ""))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .contextMenu {
            Button {
                appState.newQueryForDatabase(db)
            } label: {
                Label("New Query", systemImage: "plus.rectangle")
            }

            Button {
                db.isLoaded = false
                Task { await appState.loadSchemaForDatabase(db) }
            } label: {
                Label("Refresh Schema", systemImage: "arrow.clockwise")
            }

            Divider()

            Button {
                appState.disconnectFromDatabase(db)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash")
            }

            Divider()

            Button {
                if let fqdn = db.serverFqdn {
                    appState.revealInExplorer(databaseName: db.name, serverFqdn: fqdn)
                }
            } label: {
                Label("Show in Explorer", systemImage: "sidebar.left")
            }

            Divider()

            Button {
                if let connId = db.connectionId {
                    Task { await appState.openERDPicker(databaseName: db.name, connectionId: connId) }
                    openWindow(id: "erd")
                }
            } label: {
                Label("Database Diagram", systemImage: "rectangle.connected.to.line.below")
            }

            Button {
                if appState.openPerformanceMonitor(for: db) {
                    openWindow(id: "performance")
                }
            } label: {
                Label("Performance", systemImage: "chart.line.uptrend.xyaxis")
            }
            .disabled(db.serverFqdn == nil || !appState.authService.databases.contains(where: {
                $0.databaseName == db.name && $0.serverFqdn == db.serverFqdn
            }))
        }
        .onTapGesture(count: 2) {
            appState.newQueryForDatabase(db)
        }
    }

    private func handleReveal(_ nodeId: UUID?, scrollProxy: ScrollViewProxy? = nil) {
        guard let nodeId else { return }

        // Step 1: Expand parent server
        for server in appState.explorerNodes {
            if server.children.contains(where: { $0.id == nodeId }) {
                expandedNodes.insert(server.id)
                break
            }
        }

        // Step 2: Expand the node + scroll to it (after server children render)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expandedNodes.insert(nodeId)

            // Step 3: Scroll to the node (after it renders)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    scrollProxy?.scrollTo(nodeId, anchor: .center)
                }
            }
        }

        // Clear highlight after 2.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            appState.revealedNodeId = nil
        }
    }

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedNodes.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedNodes.insert(id)
                } else {
                    expandedNodes.remove(id)
                }
            }
        )
    }

    @ViewBuilder
    private func explorerRow(_ node: DatabaseObject) -> some View {
        ObjectExplorerRow(
            node: node,
            userDataStore: appState.userDataStore,
            onConnect: { db in Task { await appState.connectToDatabase(db) } },
            onDisconnect: { db in appState.disconnectFromDatabase(db) },
            onNewQuery: { db in appState.newQueryForDatabase(db) },
            onExpand: { obj in
                if obj.objectType == .table || obj.objectType == .view {
                    Task { await appState.loadColumnsForTable(obj) }
                } else {
                    obj.isLoaded = false
                    Task { await appState.loadSchemaForDatabase(obj) }
                }
            }
        )
        .id(node.id)
        .background(appState.revealedNodeId == node.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }

    // MARK: - Manual connections section

    /// Source of a manual-connection row in the Explorer's "Manual Connections"
    /// section. We stitch together the user's favorites + group members because a
    /// manual entry might live in either (or both) — connect routing dispatches
    /// to the right AppState helper based on which object originated the row.
    private enum ManualSource {
        case favorite(FavoriteDatabase)
        case member(GroupMember)
    }

    private struct ManualRow: Identifiable {
        let id: String       // "<server>|<db>" — stable dedup key
        let alias: String
        let databaseName: String
        let serverFqdn: String
        let kind: ConnectionKind
        let source: ManualSource
    }

    private var manualConnectionRows: [ManualRow] {
        var seen: Set<String> = []
        var rows: [ManualRow] = []
        for fav in appState.userDataStore.favorites where fav.kind != .azureEntra {
            let key = "\(fav.serverFqdn)|\(fav.databaseName)"
            if seen.insert(key).inserted {
                rows.append(ManualRow(id: key, alias: fav.displayName,
                                      databaseName: fav.databaseName,
                                      serverFqdn: fav.serverFqdn, kind: fav.kind,
                                      source: .favorite(fav)))
            }
        }
        for group in appState.userDataStore.groups {
            for m in group.members where m.kind != .azureEntra {
                let key = "\(m.serverFqdn)|\(m.databaseName)"
                if seen.insert(key).inserted {
                    rows.append(ManualRow(id: key, alias: m.alias,
                                          databaseName: m.databaseName,
                                          serverFqdn: m.serverFqdn, kind: m.kind,
                                          source: .member(m)))
                }
            }
        }
        return rows.sorted { $0.alias.lowercased() < $1.alias.lowercased() }
    }

    @ViewBuilder
    private func manualRowView(_ row: ManualRow) -> some View {
        let connected = appState.isConnected(databaseName: row.databaseName, serverFqdn: row.serverFqdn)
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)
            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(connected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(row.alias)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(connected ? .primary : .secondary)
                    Text(row.kind == .manualSqlAuth ? "SQL" : "Entra")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(Color.purple.opacity(0.4), lineWidth: 0.5))
                }
                Text("\(row.databaseName)  ·  \(row.serverFqdn)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if connected {
                if let node = appState.findConnectedNode(databaseName: row.databaseName, serverFqdn: row.serverFqdn) {
                    appState.newQueryForDatabase(node)
                }
            } else {
                Task {
                    switch row.source {
                    case .favorite(let f): await appState.connectToFavorite(f)
                    case .member(let m):   await appState.connectToGroupMember(m)
                    }
                }
            }
        }
        .contextMenu {
            if connected {
                Button {
                    if let node = appState.findConnectedNode(databaseName: row.databaseName, serverFqdn: row.serverFqdn) {
                        appState.newQueryForDatabase(node)
                    }
                } label: { Label("New Query", systemImage: "plus.rectangle") }
                Button {
                    appState.disconnect(databaseName: row.databaseName, serverFqdn: row.serverFqdn)
                } label: { Label("Disconnect", systemImage: "bolt.slash") }
            } else {
                Button {
                    Task {
                        switch row.source {
                        case .favorite(let f): await appState.connectToFavorite(f)
                        case .member(let m):   await appState.connectToGroupMember(m)
                        }
                    }
                } label: { Label("Connect", systemImage: "bolt.fill") }
            }
        }
    }

    /// All currently connected database nodes
    private var connectedDatabases: [DatabaseObject] {
        appState.explorerNodes.flatMap { server in
            server.children.filter { $0.objectType == .database && $0.isConnected }
        }
    }

    /// All distinct schemas from connected database table/view/proc/function nodes
    private var availableSchemas: [String] {
        var schemas = Set<String>()
        for db in connectedDatabases {
            for folder in db.children {
                for item in folder.children {
                    if let dot = item.name.firstIndex(of: ".") {
                        schemas.insert(String(item.name[item.name.startIndex..<dot]))
                    }
                }
            }
        }
        return schemas.sorted()
    }

    private var isFilterActive: Bool {
        !selectedSchemas.isEmpty || !explorerSearchText.isEmpty
    }

    /// All filterable objects from connected databases, flat, matching current filters
    private var filteredFlatItems: [(folder: String, items: [DatabaseObject])] {
        var result: [(folder: String, items: [DatabaseObject])] = []
        let folderNames = ["Tables", "Views", "Stored Procedures", "Functions"]
        for db in connectedDatabases {
            for folder in db.children where folderNames.contains(folder.name) {
                let matching = folder.children.filter { item in
                    let name = item.name
                    if !selectedSchemas.isEmpty {
                        if let dot = name.firstIndex(of: ".") {
                            let s = String(name[name.startIndex..<dot])
                            if !selectedSchemas.contains(s) { return false }
                        }
                    }
                    if !explorerSearchText.isEmpty {
                        if !name.lowercased().contains(explorerSearchText.lowercased()) { return false }
                    }
                    return true
                }
                if !matching.isEmpty {
                    result.append((folder: folder.name, items: matching))
                }
            }
        }
        return result
    }

    private var explorerContent: some View {
        Group {
            if appState.explorerNodes.isEmpty && manualConnectionRows.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "cylinder")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    if !appState.authService.isSignedIn {
                        Text("No databases yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Sign in to browse Azure SQL, or click")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("New")
                                .font(.system(size: 11, weight: .medium))
                            Text("at the top to add a manual connection")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text("No databases")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            } else if isFilterActive {
                // Flat filtered list — avoids NSOutlineView crash from dynamic tree changes
                List {
                    ForEach(filteredFlatItems, id: \.folder) { group in
                        Section {
                            ForEach(group.items) { item in
                                explorerRow(item)
                            }
                        } header: {
                            Text("\(group.folder.uppercased()) (\(group.items.count))")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                // Full tree view (no filters active)
                ScrollViewReader { scrollProxy in
                List {
                    // Connected databases pinned at top
                    if !connectedDatabases.isEmpty {
                        Section {
                            ForEach(connectedDatabases) { db in
                                if db.isExpandable && !db.children.isEmpty {
                                    DisclosureGroup(isExpanded: expandedBinding(db.id)) {
                                        ForEach(db.children) { folder in
                                            if folder.isExpandable && !folder.children.isEmpty {
                                                DisclosureGroup(isExpanded: expandedBinding(folder.id)) {
                                                    ForEach(folder.children) { item in
                                                        if item.isExpandable {
                                                            DisclosureGroup(isExpanded: expandedBinding(item.id)) {
                                                                ForEach(item.children) { col in
                                                                    explorerRow(col)
                                                                }
                                                            } label: {
                                                                explorerRow(item)
                                                            }
                                                        } else {
                                                            explorerRow(item)
                                                        }
                                                    }
                                                } label: {
                                                    explorerRow(folder)
                                                }
                                            } else {
                                                explorerRow(folder)
                                            }
                                        }
                                    } label: {
                                        connectedDbLabel(db)
                                    }
                                } else {
                                    connectedDbLabel(db)
                                }
                            }
                        } header: {
                            Text("CONNECTED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.green)
                                .tracking(1)
                        }
                    }

                    // Saved manual connections (form/connection-string entries).
                    // Distinct from Azure-discovered databases — clicking connects
                    // using stored Keychain credentials (or current Entra token).
                    if !manualConnectionRows.isEmpty {
                        Section {
                            ForEach(manualConnectionRows) { row in
                                manualRowView(row)
                            }
                        } header: {
                            Text("MANUAL CONNECTIONS")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.purple)
                                .tracking(1)
                        }
                    }

                    // Full server/database tree
                    Section {
                        ForEach(appState.explorerNodes) { server in
                            DisclosureGroup(isExpanded: expandedBinding(server.id)) {
                                ForEach(server.children) { db in
                                    if db.isExpandable && !db.children.isEmpty {
                                        DisclosureGroup(isExpanded: expandedBinding(db.id)) {
                                            ForEach(db.children) { folder in
                                                if folder.isExpandable && !folder.children.isEmpty {
                                                    DisclosureGroup(isExpanded: expandedBinding(folder.id)) {
                                                        ForEach(folder.children) { item in
                                                            if item.isExpandable {
                                                                DisclosureGroup(isExpanded: expandedBinding(item.id)) {
                                                                    ForEach(item.children) { col in
                                                                        explorerRow(col)
                                                                    }
                                                                } label: {
                                                                    explorerRow(item)
                                                                }
                                                            } else {
                                                                explorerRow(item)
                                                            }
                                                        }
                                                    } label: {
                                                        explorerRow(folder)
                                                    }
                                                } else {
                                                    explorerRow(folder)
                                                }
                                            }
                                        } label: {
                                            explorerRow(db)
                                        }
                                    } else {
                                        explorerRow(db)
                                    }
                                }
                            } label: {
                                explorerRow(server)
                            }
                        }
                    } header: {
                        Text("ALL DATABASES")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                    }
                }
                .listStyle(.sidebar)
                .onAppear {
                    handleReveal(appState.revealedNodeId, scrollProxy: scrollProxy)
                }
                .onChange(of: appState.revealedNodeId) { _, nodeId in
                    handleReveal(nodeId, scrollProxy: scrollProxy)
                }
                } // end ScrollViewReader
            }
        }
    }
}

// MARK: - Make DatabaseObject work with List children
extension DatabaseObject {
    var optionalChildren: [DatabaseObject]? {
        children.isEmpty && !isExpandable ? nil : children
    }
}

// MARK: - Custom Tab Button

struct QueryTabButton: View {
    let tab: QueryTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            // Executing indicator
            if tab.isExecuting {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }

            Text(tab.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            // Close button — visible on hover or when selected
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovering || isSelected ? Color.secondary : Color.clear)
            }
            .buttonStyle(.plain)
            .help("Close tab (⌘W)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.15) : (isHovering ? Color.white.opacity(0.05) : Color.clear))
        .cornerRadius(5)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}
