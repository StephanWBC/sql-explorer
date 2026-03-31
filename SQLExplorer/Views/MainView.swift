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
    @State private var explorerWidth: CGFloat = 280
    @State private var selectedSidebarTab: SidebarTab = .explorer
    @State private var expandedNodes: Set<UUID> = []

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
                    TabView(selection: $appState.selectedTabId) {
                        ForEach($appState.queryTabs) { $tab in
                            QueryEditorView(tab: $tab)
                                .tabItem {
                                    HStack(spacing: 4) {
                                        Text(tab.title)
                                        Button {
                                            appState.closeTab(tab.id)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .tag(tab.id as UUID?)
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
        .onChange(of: appState.authService.databases) { _, newDatabases in
            appState.buildExplorerFromDatabases(newDatabases)
        }
        .onReceive(appState.authService.$databases) { newDatabases in
            if !newDatabases.isEmpty {
                appState.buildExplorerFromDatabases(newDatabases)
            }
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
            onExpand: { db in
                db.isLoaded = false
                Task { await appState.loadSchemaForDatabase(db) }
            }
        )
        .id(node.id)
        .background(appState.revealedNodeId == node.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }

    /// All currently connected database nodes
    private var connectedDatabases: [DatabaseObject] {
        appState.explorerNodes.flatMap { server in
            server.children.filter { $0.objectType == .database && $0.isConnected }
        }
    }

    private var explorerContent: some View {
        Group {
            if appState.explorerNodes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "cylinder")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No databases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                List {
                    // Connected databases pinned at top — same expandable view as All Databases
                    if !connectedDatabases.isEmpty {
                        Section {
                            ForEach(connectedDatabases) { db in
                                if db.isExpandable && !db.children.isEmpty {
                                    DisclosureGroup(isExpanded: expandedBinding(db.id)) {
                                        ForEach(db.children) { child in
                                            if child.isExpandable && !child.children.isEmpty {
                                                DisclosureGroup(isExpanded: expandedBinding(child.id)) {
                                                    ForEach(child.children) { leaf in
                                                        explorerRow(leaf)
                                                    }
                                                } label: {
                                                    explorerRow(child)
                                                }
                                            } else {
                                                explorerRow(child)
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

                    // Full server/database tree — DisclosureGroup for programmatic expand
                    Section {
                        ForEach(appState.explorerNodes) { server in
                            DisclosureGroup(isExpanded: expandedBinding(server.id)) {
                                ForEach(server.children) { db in
                                    if db.isExpandable && !db.children.isEmpty {
                                        DisclosureGroup(isExpanded: expandedBinding(db.id)) {
                                            ForEach(db.children) { child in
                                                if child.isExpandable && !child.children.isEmpty {
                                                    DisclosureGroup(isExpanded: expandedBinding(child.id)) {
                                                        ForEach(child.children) { leaf in
                                                            explorerRow(leaf)
                                                        }
                                                    } label: {
                                                        explorerRow(child)
                                                    }
                                                } else {
                                                    explorerRow(child)
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
