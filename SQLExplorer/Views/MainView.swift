import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    // No toolbar — all actions via sidebar or keyboard shortcuts
    @State private var explorerWidth: CGFloat = 260

    var body: some View {
        HSplitView {
            // Left: Object Explorer
            VStack(spacing: 0) {
                // Account banner — always visible, observes authService directly
                AccountBannerView(authService: appState.authService)

                Divider()

                // Explorer header
                HStack {
                    Text("EXPLORER")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.bar)

                Divider()

                // Tree view
                if appState.explorerNodes.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "cylinder")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text("No connections")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(appState.explorerNodes, children: \.optionalChildren) { node in
                        ObjectExplorerRow(
                            node: node,
                            onConnect: { db in Task { await appState.connectToDatabase(db) } },
                            onDisconnect: { db in appState.disconnectFromDatabase(db) },
                            onNewQuery: { db in appState.newQueryForDatabase(db) }
                        )
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 200, idealWidth: explorerWidth, maxWidth: 400)

            // Right: Query editor area
            VStack(spacing: 0) {
                if appState.queryTabs.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("SQL Explorer")
                            .font(.title)
                            .fontWeight(.light)
                            .foregroundStyle(.secondary)
                        Text("Connect to a server and open a new query tab.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 16) {
                            Label("⌘N connect", systemImage: "")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Label("⌘T new query", systemImage: "")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                            Label("⌘↵ execute", systemImage: "")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Tab bar + editor
                    TabView(selection: $appState.selectedTabId) {
                        ForEach($appState.queryTabs) { $tab in
                            QueryEditorView(tab: $tab)
                                .tabItem { Text(tab.title) }
                                .tag(tab.id as UUID?)
                        }
                    }
                }
            }
        }
        .toolbar(.hidden)
        // Status bar
        .onChange(of: appState.authService.databases) { _, newDatabases in
            appState.buildExplorerFromDatabases(newDatabases)
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
                .environmentObject(appState)
        }
    }

    private func executeCurrentQuery() async {
        guard let tabId = appState.selectedTabId,
              let tabIdx = appState.queryTabs.firstIndex(where: { $0.id == tabId }),
              !appState.queryTabs[tabIdx].sql.isEmpty
        else { return }

        appState.queryTabs[tabIdx].isExecuting = true
        appState.statusMessage = "Executing..."

        let sql = appState.queryTabs[tabIdx].sql
        let connId = appState.queryTabs[tabIdx].connectionId

        do {
            let result = try await appState.connectionManager.executeQuery(sql, connectionId: connId)
            appState.queryTabs[tabIdx].result = result
            appState.statusMessage = "Done — \(result.rows.count) rows in \(result.elapsedMs)ms"
        } catch {
            appState.queryTabs[tabIdx].result = QueryResult(errorMessage: error.localizedDescription)
            appState.statusMessage = "Error: \(error.localizedDescription)"
        }

        appState.queryTabs[tabIdx].isExecuting = false
    }
}

// MARK: - Make DatabaseObject work with List children
extension DatabaseObject {
    var optionalChildren: [DatabaseObject]? {
        children.isEmpty && !isExpandable ? nil : children
    }
}
