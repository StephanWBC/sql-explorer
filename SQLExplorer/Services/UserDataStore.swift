import Foundation

@MainActor
class UserDataStore: ObservableObject {
    @Published var favorites: [FavoriteDatabase] = []
    @Published var groups: [DatabaseGroup] = []

    private static let storeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sqlexplorer")
    private static let file = storeDir.appendingPathComponent("userdata.json")

    private struct StoreData: Codable {
        var favorites: [FavoriteDatabase] = []
        var groups: [DatabaseGroup] = []
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let store = try? JSONDecoder().decode(StoreData.self, from: data) else { return }
        favorites = store.favorites
        groups = store.groups
    }

    func save() {
        let store = StoreData(favorites: favorites, groups: groups)
        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    // MARK: - Favorites

    func isFavorite(databaseName: String, serverFqdn: String) -> Bool {
        favorites.contains { $0.databaseName == databaseName && $0.serverFqdn == serverFqdn }
    }

    func toggleFavorite(databaseName: String, serverFqdn: String, subscriptionId: String, subscriptionName: String) {
        if let idx = favorites.firstIndex(where: { $0.databaseName == databaseName && $0.serverFqdn == serverFqdn }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(FavoriteDatabase(
                databaseName: databaseName, serverFqdn: serverFqdn,
                subscriptionId: subscriptionId, subscriptionName: subscriptionName))
        }
        save()
    }

    func removeFavorite(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    // MARK: - Groups

    func addGroup(name: String) -> DatabaseGroup {
        let group = DatabaseGroup(name: name)
        groups.append(group)
        save()
        return group
    }

    func removeGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        save()
    }

    func renameGroup(_ id: UUID, to name: String) {
        if let idx = groups.firstIndex(where: { $0.id == id }) {
            groups[idx].name = name
            save()
        }
    }

    func addToGroup(groupId: UUID, databaseName: String, serverFqdn: String,
                    subscriptionId: String, subscriptionName: String, alias: String) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        // Don't add duplicates
        if groups[idx].members.contains(where: { $0.databaseName == databaseName && $0.serverFqdn == serverFqdn }) { return }
        groups[idx].members.append(GroupMember(
            databaseName: databaseName, serverFqdn: serverFqdn,
            subscriptionId: subscriptionId, subscriptionName: subscriptionName, alias: alias))
        save()
    }

    func removeFromGroup(groupId: UUID, memberId: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[idx].members.removeAll { $0.id == memberId }
        save()
    }

    func updateAlias(groupId: UUID, memberId: UUID, alias: String) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupId }),
              let mIdx = groups[gIdx].members.firstIndex(where: { $0.id == memberId }) else { return }
        groups[gIdx].members[mIdx].alias = alias
        save()
    }
}
