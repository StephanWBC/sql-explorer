import SwiftUI

@MainActor
class AppState: ObservableObject {
    let connectionManager = ConnectionManager()
    let connectionStore = ConnectionStore()
    let authService = AuthService()
    let queryService = QueryExecutionService()
    let explorerService = ObjectExplorerService()
    let userDataStore = UserDataStore()
    let schemaCache = SchemaCache()

    @Published var activeConnectionId: UUID?
    @Published var statusMessage: String = "Ready"
    @Published var currentDatabase: String = ""

    @Published var explorerNodes: [DatabaseObject] = []
    @Published var revealedNodeId: UUID?  // Set this to scroll to + expand a node
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

    // MARK: - Connection Status Lookup (used by ALL tabs: Explorer, Favorites, Groups)

    /// Check if a specific database on a specific server is connected
    func isConnected(databaseName: String, serverFqdn: String) -> Bool {
        findExplorerNode(databaseName: databaseName, serverFqdn: serverFqdn)?.isConnected ?? false
    }

    /// Get the connectionId for a connected database (for query tabs)
    func connectionId(databaseName: String, serverFqdn: String) -> UUID? {
        findExplorerNode(databaseName: databaseName, serverFqdn: serverFqdn)?.connectionId
    }

    // MARK: - Build Explorer Tree

    func buildExplorerFromDatabases(_ databases: [AzureDatabase]) {
        // Preserve existing connection state when rebuilding
        var connectedDbs: [String: (UUID, Bool)] = [:]  // key -> (connectionId, isLoaded)
        for node in allDatabaseNodes() {
            if node.isConnected, let connId = node.connectionId, let fqdn = node.serverFqdn {
                connectedDbs["\(node.name)@\(fqdn)"] = (connId, node.isLoaded)
            }
        }

        explorerNodes.removeAll()

        let grouped = Dictionary(grouping: databases, by: { $0.serverFqdn })

        for (serverFqdn, dbs) in grouped.sorted(by: { $0.key < $1.key }) {
            let shortName = serverFqdn.replacingOccurrences(of: ".database.windows.net", with: "")

            let serverNode = DatabaseObject(name: shortName, objectType: .server, isExpandable: true)
            serverNode.isLoaded = true

            for db in dbs.sorted(by: { $0.databaseName < $1.databaseName }) {
                let dbNode = DatabaseObject(
                    name: db.databaseName, database: db.databaseName,
                    objectType: .database, isExpandable: false)
                dbNode.serverFqdn = db.serverFqdn

                // Restore connection state if previously connected
                let key = "\(db.databaseName)@\(db.serverFqdn)"
                if let (connId, _) = connectedDbs[key] {
                    dbNode.connectionId = connId
                    dbNode.isConnected = true
                    dbNode.isExpandable = true
                }

                serverNode.children.append(dbNode)
            }

            explorerNodes.append(serverNode)
        }

        statusMessage = "\(databases.count) database(s) across \(grouped.count) server(s)"
    }

    // MARK: - Connect / Disconnect

    func connectToDatabase(_ node: DatabaseObject) async {
        guard node.objectType == .database,
              let serverFqdn = node.serverFqdn ?? findServerFqdn(for: node),
              !node.isConnected else { return }

        // DEDUP: Check if already connected to this database on this server
        if let existing = findExplorerNode(databaseName: node.name, serverFqdn: serverFqdn),
           existing.isConnected {
            statusMessage = "\(node.name) is already connected"
            return
        }

        node.isConnecting = true
        statusMessage = "Connecting to \(node.name)..."

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
            node.isExpandable = true
            activeConnectionId = connId
            currentDatabase = node.name
            statusMessage = "Connected to \(node.name)"

            await loadSchemaForDatabase(node)

            // Auto-expand in explorer tree
            revealedNodeId = node.id
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }

        node.isConnecting = false
    }

    func disconnectFromDatabase(_ node: DatabaseObject) {
        guard let connId = node.connectionId, node.isConnected else { return }
        connectionManager.disconnect(connId)
        node.isConnected = false
        node.isExpandable = false
        node.isLoaded = false
        node.children.removeAll()
        node.connectionId = nil
        statusMessage = "Disconnected from \(node.name)"

        if activeConnectionId == connId {
            let connected = allDatabaseNodes().first { $0.isConnected }
            activeConnectionId = connected?.connectionId
            currentDatabase = connected?.name ?? ""
        }
    }

    func newQueryForDatabase(_ node: DatabaseObject) {
        guard let connId = node.connectionId, node.isConnected else { return }

        // Find server name
        let serverName = node.serverFqdn?.replacingOccurrences(of: ".database.windows.net", with: "") ?? ""

        // Find group alias if this database belongs to any group
        var groupAlias = ""
        for group in userDataStore.groups {
            if let member = group.members.first(where: {
                $0.databaseName == node.name && $0.serverFqdn == (node.serverFqdn ?? "")
            }) {
                groupAlias = "\(group.name) > \(member.alias)"
                break
            }
        }

        let tab = QueryTab(
            title: "\(node.name) — Query \(queryTabs.count + 1)",
            connectionId: connId, database: node.name,
            serverName: serverName, groupAlias: groupAlias)
        queryTabs.append(tab)
        selectedTabId = tab.id
        activeConnectionId = connId
        currentDatabase = node.name
    }

    // MARK: - Connect from Favorites / Groups (ALWAYS uses real explorer nodes)

    func connectToFavorite(_ fav: FavoriteDatabase) async {
        let node = findExplorerNode(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn)
        guard let node else {
            statusMessage = "Database not found in current subscription. Switch subscription first."
            return
        }
        await connectToDatabase(node)
    }

    func connectToGroupMember(_ member: GroupMember) async {
        let node = findExplorerNode(databaseName: member.databaseName, serverFqdn: member.serverFqdn)
        guard let node else {
            statusMessage = "Database not found in current subscription. Switch subscription first."
            return
        }
        await connectToDatabase(node)
    }

    func newQueryForFavorite(_ fav: FavoriteDatabase) {
        guard let node = findExplorerNode(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn),
              node.isConnected else { return }
        newQueryForDatabase(node)
    }

    func newQueryForGroupMember(_ member: GroupMember) {
        guard let node = findExplorerNode(databaseName: member.databaseName, serverFqdn: member.serverFqdn),
              node.isConnected else { return }
        newQueryForDatabase(node)
    }

    // MARK: - Disconnect by server+database (for Favorites/Groups)

    func disconnect(databaseName: String, serverFqdn: String) {
        guard let node = findExplorerNode(databaseName: databaseName, serverFqdn: serverFqdn) else { return }
        disconnectFromDatabase(node)
    }

    // MARK: - Tab Management

    func closeTab(_ tabId: UUID) {
        guard let idx = queryTabs.firstIndex(where: { $0.id == tabId }) else { return }
        queryTabs.remove(at: idx)
        if selectedTabId == tabId {
            selectedTabId = queryTabs.last?.id
        }
    }

    func closeCurrentTab() {
        guard let tabId = selectedTabId else { return }
        closeTab(tabId)
    }

    // MARK: - Reveal in Explorer

    func revealInExplorer(databaseName: String, serverFqdn: String) {
        guard let node = findExplorerNode(databaseName: databaseName, serverFqdn: serverFqdn) else { return }
        // Just set the revealedNodeId — the MainView onChange handler
        // will expand the correct parent server + node in expandedNodes
        revealedNodeId = node.id
    }

    // MARK: - Helpers

    private func findExplorerNode(databaseName: String, serverFqdn: String) -> DatabaseObject? {
        for server in explorerNodes {
            if let db = server.children.first(where: {
                $0.name == databaseName && $0.serverFqdn == serverFqdn
            }) {
                return db
            }
        }
        return nil
    }

    private func findServerFqdn(for node: DatabaseObject) -> String? {
        for server in explorerNodes {
            if server.children.contains(where: { $0.id == node.id }) {
                return server.name + ".database.windows.net"
            }
        }
        return nil
    }

    private func allDatabaseNodes() -> [DatabaseObject] {
        explorerNodes.flatMap { $0.children.filter { $0.objectType == .database } }
    }

    // MARK: - Schema Loading

    func loadSchemaForDatabase(_ node: DatabaseObject) async {
        guard node.objectType == .database, node.isConnected,
              let connId = node.connectionId, !node.isLoaded else { return }

        node.children.removeAll()

        let tablesFolder = DatabaseObject(name: "Tables", objectType: .folder, isExpandable: true)
        let viewsFolder = DatabaseObject(name: "Views", objectType: .folder, isExpandable: true)
        let procsFolder = DatabaseObject(name: "Stored Procedures", objectType: .folder, isExpandable: true)
        let funcsFolder = DatabaseObject(name: "Functions", objectType: .folder, isExpandable: true)

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + t.name FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id ORDER BY s.name, t.name",
                connectionId: connId)
            for row in result.rows {
                tablesFolder.children.append(DatabaseObject(name: row[0], objectType: .table))
            }
            tablesFolder.isLoaded = true
        } catch { }

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + v.name FROM sys.views v JOIN sys.schemas s ON v.schema_id = s.schema_id ORDER BY s.name, v.name",
                connectionId: connId)
            for row in result.rows {
                viewsFolder.children.append(DatabaseObject(name: row[0], objectType: .view))
            }
            viewsFolder.isLoaded = true
        } catch { }

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + p.name FROM sys.procedures p JOIN sys.schemas s ON p.schema_id = s.schema_id WHERE p.is_ms_shipped = 0 ORDER BY s.name, p.name",
                connectionId: connId)
            for row in result.rows {
                procsFolder.children.append(DatabaseObject(name: row[0], objectType: .storedProcedure))
            }
            procsFolder.isLoaded = true
        } catch { }

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + o.name FROM sys.objects o JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('FN','IF','TF') AND o.is_ms_shipped = 0 ORDER BY s.name, o.name",
                connectionId: connId)
            for row in result.rows {
                funcsFolder.children.append(DatabaseObject(name: row[0], objectType: .function))
            }
            funcsFolder.isLoaded = true
        } catch { }

        node.children = [tablesFolder, viewsFolder, procsFolder, funcsFolder]
        node.isLoaded = true
        objectWillChange.send()

        // Rebuild IntelliSense completions with new schema
        schemaCache.updateFromExplorerNodes(explorerNodes)
        CompletionProvider.rebuild(schema: schemaCache)
    }

    // MARK: - Legacy (manual connections)

    func addServerToExplorer(name: String, connectionId: UUID, groupId: UUID?, environmentLabel: String?) {
        let serverNode = DatabaseObject(name: name, connectionId: connectionId, objectType: .server, isExpandable: true)
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
                let idx = explorerNodes.firstIndex(where: { $0.objectType != .connectionGroup }) ?? explorerNodes.count
                explorerNodes.insert(groupNode, at: idx)
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
    var serverName: String = ""   // e.g. "wbcazsql01-development"
    var groupAlias: String = ""   // e.g. "BLMS > Development"
    var isSaved: Bool = false
    var savedPath: URL?
}

// Saved query model for persistence
struct SavedQuery: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sql: String
    var database: String
    var serverFqdn: String
    var savedAt: Date

    init(id: UUID = UUID(), name: String, sql: String, database: String, serverFqdn: String = "") {
        self.id = id; self.name = name; self.sql = sql; self.database = database
        self.serverFqdn = serverFqdn; self.savedAt = Date()
    }
}
