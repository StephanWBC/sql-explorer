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
    @Published var erdSchema: ERDSchema?
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

    /// Get the DatabaseObject node for a connected database (for tree expansion in Favorites/Groups)
    func findConnectedNode(databaseName: String, serverFqdn: String) -> DatabaseObject? {
        let node = findExplorerNode(databaseName: databaseName, serverFqdn: serverFqdn)
        return node?.isConnected == true ? node : nil
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

        // Batch all mutations before notifying SwiftUI to avoid
        // intermediate diff states that crash OutlineListCoordinator
        node.children = []
        node.isConnected = false
        node.isExpandable = false
        node.isLoaded = false
        node.connectionId = nil
        objectWillChange.send()

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
        AppLogger.schema.info("Loading schema for \(node.name)")

        let tablesFolder = DatabaseObject(name: "Tables", objectType: .folder, isExpandable: true)
        let viewsFolder = DatabaseObject(name: "Views", objectType: .folder, isExpandable: true)
        let procsFolder = DatabaseObject(name: "Stored Procedures", objectType: .folder, isExpandable: true)
        let funcsFolder = DatabaseObject(name: "Functions", objectType: .folder, isExpandable: true)

        var schemaErrors: [String] = []

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + t.name FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id ORDER BY s.name, t.name",
                connectionId: connId)
            for row in result.rows {
                let tableNode = DatabaseObject(name: row[0], objectType: .table, isExpandable: true)
                tableNode.connectionId = connId
                tablesFolder.children.append(tableNode)
            }
            tablesFolder.isLoaded = true
        } catch { schemaErrors.append("Tables") }

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + v.name FROM sys.views v JOIN sys.schemas s ON v.schema_id = s.schema_id ORDER BY s.name, v.name",
                connectionId: connId)
            for row in result.rows {
                let viewNode = DatabaseObject(name: row[0], objectType: .view, isExpandable: true)
                viewNode.connectionId = connId
                viewsFolder.children.append(viewNode)
            }
            viewsFolder.isLoaded = true
        } catch { schemaErrors.append("Views") }

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + p.name FROM sys.procedures p JOIN sys.schemas s ON p.schema_id = s.schema_id WHERE p.is_ms_shipped = 0 ORDER BY s.name, p.name",
                connectionId: connId)
            for row in result.rows {
                procsFolder.children.append(DatabaseObject(name: row[0], objectType: .storedProcedure))
            }
            procsFolder.isLoaded = true
        } catch { schemaErrors.append("Stored Procedures") }

        do {
            let result = try await connectionManager.executeQuery(
                "SELECT s.name + '.' + o.name FROM sys.objects o JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('FN','IF','TF') AND o.is_ms_shipped = 0 ORDER BY s.name, o.name",
                connectionId: connId)
            for row in result.rows {
                funcsFolder.children.append(DatabaseObject(name: row[0], objectType: .function))
            }
            funcsFolder.isLoaded = true
        } catch { schemaErrors.append("Functions") }

        node.children = [tablesFolder, viewsFolder, procsFolder, funcsFolder]
        node.isLoaded = true
        objectWillChange.send()

        if !schemaErrors.isEmpty {
            statusMessage = "Schema loaded with errors (\(schemaErrors.joined(separator: ", ")) failed)"
        }

        // Rebuild IntelliSense completions with new schema
        schemaCache.updateFromExplorerNodes(explorerNodes)
        CompletionProvider.rebuild(schema: schemaCache)
    }

    // MARK: - Column Loading (lazy, on table expand)

    func loadColumnsForTable(_ node: DatabaseObject) async {
        guard (node.objectType == .table || node.objectType == .view),
              let connId = node.connectionId, !node.isLoaded else { return }

        // Parse "schema.table" from node name
        let parts = node.name.split(separator: ".", maxSplits: 1)
        let schemaName = parts.count == 2 ? String(parts[0]) : "dbo"
        let tableName = parts.count == 2 ? String(parts[1]) : node.name

        let sql = """
            SELECT c.name, tp.name AS DataType, c.max_length, c.precision, c.scale, c.is_nullable,
                   CASE WHEN ic.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPK,
                   CASE WHEN fkc.parent_column_id IS NOT NULL THEN 1 ELSE 0 END AS IsFK
            FROM sys.columns c
            JOIN sys.types tp ON c.user_type_id = tp.user_type_id
            LEFT JOIN sys.indexes i ON i.object_id = c.object_id AND i.is_primary_key = 1
            LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.column_id = c.column_id
            LEFT JOIN sys.foreign_key_columns fkc ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
            WHERE c.object_id = \(SQLEscaping.objectIdRef(schema: schemaName, table: tableName))
            ORDER BY c.column_id
            """

        do {
            let result = try await connectionManager.executeQuery(sql, connectionId: connId)
            var columns: [DatabaseObject] = []

            for row in result.rows {
                let colName = row[0]
                let typeName = row[1]
                let maxLen = Int(row[2]) ?? 0
                let precision = Int(row[3]) ?? 0
                let scale = Int(row[4]) ?? 0
                let nullable = row[5] == "1" || row[5].lowercased() == "true"
                let isPK = row[6] == "1"
                let isFK = row[7] == "1"

                // Build display type string
                var typeStr = typeName
                switch typeName.lowercased() {
                case "nvarchar", "nchar":
                    typeStr = maxLen == -1 ? "\(typeName)(MAX)" : "\(typeName)(\(maxLen / 2))"
                case "varchar", "char", "varbinary":
                    typeStr = maxLen == -1 ? "\(typeName)(MAX)" : "\(typeName)(\(maxLen))"
                case "decimal", "numeric":
                    typeStr = "\(typeName)(\(precision),\(scale))"
                default: break
                }

                let colNode = DatabaseObject(name: colName, objectType: .column)
                colNode.dataType = typeStr
                colNode.isPrimaryKey = isPK
                colNode.isForeignKey = isFK
                colNode.isNullable = nullable
                columns.append(colNode)
            }

            node.children = columns
            node.isLoaded = true
            objectWillChange.send()
        } catch {
            statusMessage = "Failed to load columns: \(error.localizedDescription)"
        }
    }

    // MARK: - Database Diagram (ERD)

    /// Opens ERD window immediately with blank canvas, fetches table list in background
    func openERDPicker(databaseName: String, connectionId: UUID) async {
        let schema = ERDSchema()
        schema.databaseName = databaseName
        schema.connectionId = connectionId
        // Resolve serverFqdn from explorer nodes
        for node in explorerNodes {
            for child in node.children where child.name == databaseName && child.connectionId == connectionId {
                schema.serverFqdn = child.serverFqdn ?? node.serverFqdn ?? node.name
            }
            if node.connectionId == connectionId {
                schema.serverFqdn = node.serverFqdn ?? node.name
            }
        }
        erdSchema = schema

        // Fetch table list in background — canvas is already usable
        do {
            let entries = try await ERDService.listTables(
                connectionManager: connectionManager, connectionId: connectionId)
            schema.availableTables = entries
            schema.isLoadingTableList = false
        } catch {
            schema.isLoadingTableList = false
        }
    }

    /// Add a single table to the ERD canvas
    func addTableToERD(_ entry: ERDTableEntry) async {
        guard let schema = erdSchema, let connId = schema.connectionId else { return }
        guard !schema.tablesOnCanvas.contains(entry.fullName) else { return }

        schema.isAddingTable = true

        do {
            let columns = try await ERDService.loadTableColumns(
                connectionManager: connectionManager, connectionId: connId,
                schemaName: entry.schema, tableName: entry.name)

            // Position new table: find empty spot
            let cols = max(Int(ceil(sqrt(Double(schema.tables.count + 1)))), 1)
            let idx = schema.tables.count
            let x = CGFloat(idx % cols) * 280 + 40
            let y = CGFloat(idx / cols) * 240 + 40

            let table = ERDTable(schema: entry.schema, name: entry.name,
                                 columns: columns, position: CGPoint(x: x, y: y))
            schema.tables.append(table)

            // Load or reuse cached FKs
            if schema.cachedForeignKeys == nil {
                schema.cachedForeignKeys = try await ERDService.loadAllForeignKeys(
                    connectionManager: connectionManager, connectionId: connId)
            }

            let allFKs = schema.cachedForeignKeys!
            let names = schema.tablesOnCanvas

            // Derive on-canvas relationships from cache
            schema.relationships = ERDService.filterRelationships(from: allFKs, tablesOnCanvas: names)

            // Derive related tables not on canvas
            schema.relatedTables = ERDService.filterRelatedTables(from: allFKs, tablesOnCanvas: names)
        } catch {
            statusMessage = "Failed to add table to diagram: \(error.localizedDescription)"
        }

        schema.isAddingTable = false
    }

    /// Remove a table from the ERD canvas
    func removeTableFromERD(_ table: ERDTable) async {
        guard let schema = erdSchema else { return }
        schema.tables.removeAll { $0.id == table.id }

        let names = schema.tablesOnCanvas

        if let allFKs = schema.cachedForeignKeys {
            // Recompute from cache (no network call needed)
            schema.relationships = ERDService.filterRelationships(from: allFKs, tablesOnCanvas: names)
            schema.relatedTables = ERDService.filterRelatedTables(from: allFKs, tablesOnCanvas: names)
        } else {
            // Fallback: remove stale relationships directly
            schema.relationships.removeAll { $0.fromTable == table.fullName || $0.toTable == table.fullName }
            schema.relatedTables.removeAll()
        }
    }

    // MARK: - Diagram Save / Load

    func saveDiagram(name: String) {
        guard let schema = erdSchema else { return }
        let tables = schema.tables.map {
            SavedDiagramTable(schema: $0.schema, name: $0.name, x: $0.position.x, y: $0.position.y)
        }
        let diagram = SavedDiagram(
            id: schema.savedDiagramId ?? UUID(),
            name: name,
            databaseName: schema.databaseName,
            serverFqdn: schema.serverFqdn,
            tables: tables
        )
        userDataStore.saveDiagram(diagram)
        schema.savedDiagramId = diagram.id
        schema.savedDiagramName = name
        statusMessage = "Diagram \"\(name)\" saved"
        objectWillChange.send()
    }

    func loadDiagram(_ diagram: SavedDiagram) async {
        guard let schema = erdSchema, let connId = schema.connectionId else { return }
        guard schema.databaseName == diagram.databaseName else {
            statusMessage = "Diagram is for database \"\(diagram.databaseName)\""
            return
        }

        schema.isAddingTable = true
        schema.tables.removeAll()
        schema.relationships.removeAll()
        schema.relatedTables.removeAll()
        schema.cachedForeignKeys = nil
        schema.savedDiagramId = diagram.id
        schema.savedDiagramName = diagram.name

        do {
            for saved in diagram.tables {
                let columns = try await ERDService.loadTableColumns(
                    connectionManager: connectionManager, connectionId: connId,
                    schemaName: saved.schema, tableName: saved.name)
                let table = ERDTable(schema: saved.schema, name: saved.name,
                                     columns: columns,
                                     position: CGPoint(x: saved.x, y: saved.y))
                schema.tables.append(table)
            }

            // Load FKs and compute relationships + related tables
            if schema.cachedForeignKeys == nil {
                schema.cachedForeignKeys = try await ERDService.loadAllForeignKeys(
                    connectionManager: connectionManager, connectionId: connId)
            }
            let allFKs = schema.cachedForeignKeys!
            let names = schema.tablesOnCanvas
            schema.relationships = ERDService.filterRelationships(from: allFKs, tablesOnCanvas: names)
            schema.relatedTables = ERDService.filterRelatedTables(from: allFKs, tablesOnCanvas: names)
            statusMessage = "Loaded diagram \"\(diagram.name)\""
        } catch {
            statusMessage = "Failed to load diagram: \(error.localizedDescription)"
        }

        schema.isAddingTable = false
    }

    func deleteDiagram(_ id: UUID) {
        userDataStore.deleteSavedDiagram(id)
        if erdSchema?.savedDiagramId == id {
            erdSchema?.savedDiagramId = nil
            erdSchema?.savedDiagramName = ""
        }
        objectWillChange.send()
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
