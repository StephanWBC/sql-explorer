import SwiftUI

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

    /// Build the Explorer tree from discovered Azure databases — grouped by server
    func buildExplorerFromDatabases(_ databases: [AzureDatabase]) {
        explorerNodes.removeAll()

        // Group by server FQDN
        let grouped = Dictionary(grouping: databases, by: { $0.serverFqdn })

        for (serverFqdn, dbs) in grouped.sorted(by: { $0.key < $1.key }) {
            let shortName = serverFqdn.replacingOccurrences(of: ".database.windows.net", with: "")

            let serverNode = DatabaseObject(
                name: shortName,
                objectType: .server,
                isExpandable: true
            )
            serverNode.isLoaded = true  // children are pre-populated

            for db in dbs.sorted(by: { $0.databaseName < $1.databaseName }) {
                let dbNode = DatabaseObject(
                    name: db.databaseName,
                    database: db.databaseName,
                    objectType: .database,
                    isExpandable: true
                )
                // Store the full server FQDN for connection later
                dbNode.serverFqdn = db.serverFqdn
                serverNode.children.append(dbNode)
            }

            explorerNodes.append(serverNode)
        }

        statusMessage = "\(databases.count) database(s) across \(grouped.count) server(s)"
    }

    /// Add a server node (for manual connections)
    func addServerToExplorer(name: String, connectionId: UUID, groupId: UUID?, environmentLabel: String?) {
        let serverNode = DatabaseObject(
            name: name,
            connectionId: connectionId,
            objectType: .server,
            isExpandable: true
        )
        serverNode.environmentLabel = environmentLabel

        if let groupId {
            if let groupNode = explorerNodes.first(where: { $0.objectType == .connectionGroup && $0.groupId == groupId }) {
                groupNode.children.append(serverNode)
                objectWillChange.send()
            } else if let group = connectionStore.groups.first(where: { $0.id == groupId }) {
                let groupNode = DatabaseObject(name: group.name, objectType: .connectionGroup, isExpandable: true)
                groupNode.groupId = groupId
                groupNode.isLoaded = true
                groupNode.children.append(serverNode)
                let insertIdx = explorerNodes.firstIndex(where: { $0.objectType != .connectionGroup }) ?? explorerNodes.count
                explorerNodes.insert(groupNode, at: insertIdx)
            }
        } else {
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
