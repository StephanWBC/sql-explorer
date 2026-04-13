import Foundation

/// Distinguishes how a saved Group/Favorite member was created and how it should
/// reconnect. Defaults to `.azureEntra` when decoding pre-existing JSON without
/// a `kind` field, so existing user data keeps working unchanged.
enum ConnectionKind: String, Codable {
    case azureEntra        // Discovered via Azure ARM, reconnects with Entra SQL token
    case manualSqlAuth     // User-entered host/db + sa-style credentials in Keychain
    case manualEntra       // User-entered host/db, reconnects with Entra SQL token
}

struct FavoriteDatabase: Codable, Identifiable, Hashable {
    let id: UUID
    let databaseName: String
    let serverFqdn: String
    var subscriptionId: String?
    var subscriptionName: String?
    var alias: String?

    // Connection metadata — used to reconnect manual entries and (post-rework) to
    // brand the row appropriately. Optional so old JSON decodes without these fields.
    var kind: ConnectionKind
    var port: Int?
    var username: String?
    var keychainRef: String?    // Keychain account name; only set for `.manualSqlAuth`
    var encrypt: Bool?
    var trustServerCertificate: Bool?

    var displayName: String { alias ?? databaseName }
    var shortServer: String { serverFqdn.replacingOccurrences(of: ".database.windows.net", with: "") }

    init(id: UUID = UUID(), databaseName: String, serverFqdn: String,
         subscriptionId: String? = nil, subscriptionName: String? = nil,
         alias: String? = nil, kind: ConnectionKind = .azureEntra,
         port: Int? = nil, username: String? = nil, keychainRef: String? = nil,
         encrypt: Bool? = nil, trustServerCertificate: Bool? = nil) {
        self.id = id
        self.databaseName = databaseName
        self.serverFqdn = serverFqdn
        self.subscriptionId = subscriptionId
        self.subscriptionName = subscriptionName
        self.alias = alias
        self.kind = kind
        self.port = port
        self.username = username
        self.keychainRef = keychainRef
        self.encrypt = encrypt
        self.trustServerCertificate = trustServerCertificate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        databaseName = try c.decode(String.self, forKey: .databaseName)
        serverFqdn = try c.decode(String.self, forKey: .serverFqdn)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        subscriptionName = try c.decodeIfPresent(String.self, forKey: .subscriptionName)
        alias = try c.decodeIfPresent(String.self, forKey: .alias)
        kind = (try c.decodeIfPresent(ConnectionKind.self, forKey: .kind)) ?? .azureEntra
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        keychainRef = try c.decodeIfPresent(String.self, forKey: .keychainRef)
        encrypt = try c.decodeIfPresent(Bool.self, forKey: .encrypt)
        trustServerCertificate = try c.decodeIfPresent(Bool.self, forKey: .trustServerCertificate)
    }
}

struct GroupMember: Codable, Identifiable, Hashable {
    let id: UUID
    let databaseName: String
    let serverFqdn: String
    var subscriptionId: String?
    var subscriptionName: String?
    var alias: String

    var kind: ConnectionKind
    var port: Int?
    var username: String?
    var keychainRef: String?
    var encrypt: Bool?
    var trustServerCertificate: Bool?

    var shortServer: String { serverFqdn.replacingOccurrences(of: ".database.windows.net", with: "") }

    init(id: UUID = UUID(), databaseName: String, serverFqdn: String,
         subscriptionId: String? = nil, subscriptionName: String? = nil,
         alias: String, kind: ConnectionKind = .azureEntra,
         port: Int? = nil, username: String? = nil, keychainRef: String? = nil,
         encrypt: Bool? = nil, trustServerCertificate: Bool? = nil) {
        self.id = id
        self.databaseName = databaseName
        self.serverFqdn = serverFqdn
        self.subscriptionId = subscriptionId
        self.subscriptionName = subscriptionName
        self.alias = alias
        self.kind = kind
        self.port = port
        self.username = username
        self.keychainRef = keychainRef
        self.encrypt = encrypt
        self.trustServerCertificate = trustServerCertificate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        databaseName = try c.decode(String.self, forKey: .databaseName)
        serverFqdn = try c.decode(String.self, forKey: .serverFqdn)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        subscriptionName = try c.decodeIfPresent(String.self, forKey: .subscriptionName)
        alias = try c.decode(String.self, forKey: .alias)
        kind = (try c.decodeIfPresent(ConnectionKind.self, forKey: .kind)) ?? .azureEntra
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        keychainRef = try c.decodeIfPresent(String.self, forKey: .keychainRef)
        encrypt = try c.decodeIfPresent(Bool.self, forKey: .encrypt)
        trustServerCertificate = try c.decodeIfPresent(Bool.self, forKey: .trustServerCertificate)
    }
}

struct DatabaseGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var members: [GroupMember]

    init(id: UUID = UUID(), name: String, members: [GroupMember] = []) {
        self.id = id; self.name = name; self.members = members
    }
}

struct SavedDiagram: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let databaseName: String
    let serverFqdn: String
    var tables: [SavedDiagramTable]
    var savedAt: Date

    init(id: UUID = UUID(), name: String, databaseName: String, serverFqdn: String,
         tables: [SavedDiagramTable] = [], savedAt: Date = Date()) {
        self.id = id; self.name = name; self.databaseName = databaseName
        self.serverFqdn = serverFqdn; self.tables = tables; self.savedAt = savedAt
    }
}

struct SavedDiagramTable: Codable, Hashable {
    let schema: String
    let name: String
    let x: Double
    let y: Double
}

struct QueryHistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let sql: String
    let database: String
    let serverName: String
    let executedAt: Date
    let rowCount: Int
    let elapsedMs: Int64
    let wasError: Bool

    init(id: UUID = UUID(), sql: String, database: String, serverName: String,
         executedAt: Date = Date(), rowCount: Int = 0, elapsedMs: Int64 = 0, wasError: Bool = false) {
        self.id = id; self.sql = sql; self.database = database; self.serverName = serverName
        self.executedAt = executedAt; self.rowCount = rowCount; self.elapsedMs = elapsedMs; self.wasError = wasError
    }
}

/// Fully describes a connection that's about to be persisted to a Group or Favorites.
/// Replaces the previous positional `addToGroup(...)` arguments and lets manual
/// connections (no subscription) be saved alongside Azure-discovered ones.
struct ConnectionDescriptor {
    let kind: ConnectionKind
    let databaseName: String
    let serverFqdn: String
    let alias: String
    let subscriptionId: String?
    let subscriptionName: String?
    let port: Int?
    let username: String?
    let keychainRef: String?
    let encrypt: Bool?
    let trustServerCertificate: Bool?

    init(kind: ConnectionKind, databaseName: String, serverFqdn: String, alias: String,
         subscriptionId: String? = nil, subscriptionName: String? = nil,
         port: Int? = nil, username: String? = nil, keychainRef: String? = nil,
         encrypt: Bool? = nil, trustServerCertificate: Bool? = nil) {
        self.kind = kind
        self.databaseName = databaseName
        self.serverFqdn = serverFqdn
        self.alias = alias
        self.subscriptionId = subscriptionId
        self.subscriptionName = subscriptionName
        self.port = port
        self.username = username
        self.keychainRef = keychainRef
        self.encrypt = encrypt
        self.trustServerCertificate = trustServerCertificate
    }
}
