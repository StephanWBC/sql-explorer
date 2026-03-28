import SwiftUI

/// Global app state — shared across all views
@MainActor
class AppState: ObservableObject {
    @Published var connectionManager = ConnectionManager()
    @Published var connectionStore = ConnectionStore()
    @Published var authService = AuthService()
    @Published var queryService = QueryExecutionService()
    @Published var explorerService = ObjectExplorerService()

    @Published var activeConnectionId: UUID?
    @Published var statusMessage: String = "Ready"
    @Published var currentDatabase: String = ""

    // Object Explorer tree
    @Published var explorerNodes: [DatabaseObject] = []

    // Query tabs
    @Published var queryTabs: [QueryTab] = []
    @Published var selectedTabId: UUID?

    var selectedTab: QueryTab? {
        get { queryTabs.first { $0.id == selectedTabId } }
        set {
            if let tab = newValue, let idx = queryTabs.firstIndex(where: { $0.id == tab.id }) {
                queryTabs[idx] = tab
            }
        }
    }

    /// Add a server node to the explorer — nested under its group if applicable
    func addServerToExplorer(name: String, connectionId: UUID, groupId: UUID?, environmentLabel: String?) {
        let serverNode = DatabaseObject(
            name: name,
            connectionId: connectionId,
            objectType: .server,
            isExpandable: true
        )
        serverNode.environmentLabel = environmentLabel

        if let groupId {
            // Find or create group node
            if let groupNode = explorerNodes.first(where: { $0.objectType == .connectionGroup && $0.groupId == groupId }) {
                groupNode.children.append(serverNode)
                objectWillChange.send()  // Force UI update
            } else {
                // Create group node from store
                if let group = connectionStore.groups.first(where: { $0.id == groupId }) {
                    let groupNode = DatabaseObject(
                        name: group.name,
                        objectType: .connectionGroup,
                        isExpandable: true
                    )
                    groupNode.groupId = groupId
                    groupNode.isLoaded = true
                    groupNode.children.append(serverNode)

                    // Insert groups at the top
                    let insertIdx = explorerNodes.firstIndex(where: { $0.objectType != .connectionGroup }) ?? explorerNodes.count
                    explorerNodes.insert(groupNode, at: insertIdx)
                }
            }
        } else {
            // No group — add at root
            explorerNodes.append(serverNode)
        }
    }
}

struct QueryTab: Identifiable {
    let id: UUID = UUID()
    var title: String
    var sql: String = ""
    var result: QueryResult?
    var isExecuting: Bool = false
    var connectionId: UUID
    var database: String
}
