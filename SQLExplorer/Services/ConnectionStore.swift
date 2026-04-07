import Foundation

/// Persists connections and groups to ~/.sqlexplorer/connections.json
@MainActor
class ConnectionStore: ObservableObject {
    @Published var groups: [ConnectionGroup] = []
    @Published var connections: [SavedConnection] = []

    private static let storeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sqlexplorer")
    private static let storeFile = storeDir.appendingPathComponent("connections.json")

    struct StoreData: Codable {
        var Groups: [ConnectionGroup] = []      // Capital G for backwards compat with .NET
        var Connections: [SavedConnection] = []  // Capital C for backwards compat with .NET
    }

    init() {
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: Self.storeFile.path) else { return }

        do {
            let data = try Data(contentsOf: Self.storeFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Try new format first
            if let store = try? decoder.decode(StoreData.self, from: data) {
                groups = store.Groups
                connections = store.Connections
                return
            }

            // Fallback: old flat array of connections (from .NET version)
            if let conns = try? decoder.decode([SavedConnection].self, from: data) {
                connections = conns
            }
        } catch {
            AppLogger.connection.error("ConnectionStore load failed: \(error.localizedDescription)")
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
            let store = StoreData(Groups: groups, Connections: connections)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(store)
            try data.write(to: Self.storeFile, options: .atomic)
        } catch {
            AppLogger.connection.error("ConnectionStore save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection CRUD

    func saveConnection(_ connection: SavedConnection) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
        } else {
            connections.append(connection)
        }
        save()
    }

    func deleteConnection(_ id: UUID) {
        connections.removeAll { $0.id == id }
        save()
    }

    // MARK: - Group CRUD

    func saveGroup(_ group: ConnectionGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
        } else {
            groups.append(group)
        }
        save()
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        // Orphan connections
        for i in connections.indices where connections[i].groupId == id {
            connections[i].groupId = nil
        }
        save()
    }

    func connectionsForGroup(_ groupId: UUID?) -> [SavedConnection] {
        connections.filter { $0.groupId == groupId }
    }

    func ungroupedConnections() -> [SavedConnection] {
        connections.filter { conn in
            conn.groupId == nil || !groups.contains(where: { $0.id == conn.groupId })
        }
    }
}
