import SwiftUI

@MainActor
class AppState: ObservableObject {
    // NOT @Published — these are ObservableObjects; views observe them directly
    let connectionManager = ConnectionManager()
    let connectionStore = ConnectionStore()
    let authService = AuthService()
    let queryService = QueryExecutionService()
    let explorerService = ObjectExplorerService()

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

    // MARK: - Database Connect / Disconnect

    func connectToDatabase(_ node: DatabaseObject) async {
        guard node.objectType == .database,
              let serverFqdn = node.serverFqdn ?? findServerFqdn(for: node),
              !node.isConnected else { return }

        node.isConnecting = true
        statusMessage = "Connecting to \(node.name)..."

        // Get SQL access token
        guard let sqlToken = await authService.getSQLToken() else {
            statusMessage = "Failed to get SQL token for \(node.name)"
            node.isConnecting = false
            return
        }

        let info = ConnectionInfo(
            name: "\(node.name) — \(serverFqdn)",
            server: serverFqdn,
            database: node.database.isEmpty ? node.name : node.database,
            authType: .entraIdInteractive,
            username: authService.userEmail,
            password: sqlToken,
            trustServerCertificate: true,
            encrypt: true
        )

        do {
            let connId = try await connectionManager.connect(info)
            node.connectionId = connId
            node.isConnected = true
            activeConnectionId = connId
            currentDatabase = node.name
            statusMessage = "Connected to \(node.name)"
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }

        node.isConnecting = false
    }

    func disconnectFromDatabase(_ node: DatabaseObject) {
        guard let connId = node.connectionId, node.isConnected else { return }
        connectionManager.disconnect(connId)
        node.isConnected = false
        node.connectionId = nil
        statusMessage = "Disconnected from \(node.name)"

        // If this was the active connection, clear it
        if activeConnectionId == connId {
            // Find another connected database
            let connected = allDatabaseNodes().first { $0.isConnected }
            activeConnectionId = connected?.connectionId
            currentDatabase = connected?.name ?? ""
        }
    }

    func newQueryForDatabase(_ node: DatabaseObject) {
        guard let connId = node.connectionId, node.isConnected else { return }
        let tab = QueryTab(
            title: "\(node.name) — Query \(queryTabs.count + 1)",
            connectionId: connId,
            database: node.name
        )
        queryTabs.append(tab)
        selectedTabId = tab.id
        activeConnectionId = connId
        currentDatabase = node.name
    }

    /// Find the server FQDN for a database node by walking up the tree
    private func findServerFqdn(for node: DatabaseObject) -> String? {
        for server in explorerNodes {
            if server.children.contains(where: { $0.id == node.id }) {
                return server.name + ".database.windows.net"
            }
        }
        return nil
    }

    /// Get all database nodes from the tree
    private func allDatabaseNodes() -> [DatabaseObject] {
        explorerNodes.flatMap { $0.children.filter { $0.objectType == .database } }
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
