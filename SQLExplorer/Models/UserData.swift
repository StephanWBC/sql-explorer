import Foundation

struct FavoriteDatabase: Codable, Identifiable, Hashable {
    let id: UUID
    let databaseName: String
    let serverFqdn: String
    let subscriptionId: String
    let subscriptionName: String
    var alias: String?

    var displayName: String { alias ?? databaseName }
    var shortServer: String { serverFqdn.replacingOccurrences(of: ".database.windows.net", with: "") }

    init(id: UUID = UUID(), databaseName: String, serverFqdn: String, subscriptionId: String, subscriptionName: String, alias: String? = nil) {
        self.id = id; self.databaseName = databaseName; self.serverFqdn = serverFqdn
        self.subscriptionId = subscriptionId; self.subscriptionName = subscriptionName; self.alias = alias
    }
}

struct GroupMember: Codable, Identifiable, Hashable {
    let id: UUID
    let databaseName: String
    let serverFqdn: String
    let subscriptionId: String
    let subscriptionName: String
    var alias: String

    var shortServer: String { serverFqdn.replacingOccurrences(of: ".database.windows.net", with: "") }

    init(id: UUID = UUID(), databaseName: String, serverFqdn: String, subscriptionId: String, subscriptionName: String, alias: String) {
        self.id = id; self.databaseName = databaseName; self.serverFqdn = serverFqdn
        self.subscriptionId = subscriptionId; self.subscriptionName = subscriptionName; self.alias = alias
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
