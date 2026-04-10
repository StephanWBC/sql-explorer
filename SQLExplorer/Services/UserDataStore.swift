import Foundation

@MainActor
class UserDataStore: ObservableObject {
    @Published var favorites: [FavoriteDatabase] = []
    @Published var groups: [DatabaseGroup] = []
    @Published var savedQueries: [SavedQuery] = []
    @Published var savedDiagrams: [SavedDiagram] = []
    @Published var queryHistory: [QueryHistoryEntry] = []

    private static let storeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sqlexplorer")
    private static let file = storeDir.appendingPathComponent("userdata.json")

    private struct StoreData: Codable {
        var favorites: [FavoriteDatabase] = []
        var groups: [DatabaseGroup] = []
        var savedQueries: [SavedQuery] = []
        var savedDiagrams: [SavedDiagram] = []
        var queryHistory: [QueryHistoryEntry] = []
    }

    init() { load() }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.file),
              let store = try? decoder.decode(StoreData.self, from: data) else { return }
        favorites = store.favorites
        groups = store.groups
        savedQueries = store.savedQueries
        savedDiagrams = store.savedDiagrams
        queryHistory = store.queryHistory
    }

    func save() {
        let store = StoreData(favorites: favorites, groups: groups, savedQueries: savedQueries, savedDiagrams: savedDiagrams, queryHistory: queryHistory)
        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store) {
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

    // MARK: - Saved Queries

    func saveQuery(_ query: SavedQuery) {
        if let idx = savedQueries.firstIndex(where: { $0.id == query.id }) {
            savedQueries[idx] = query
        } else {
            savedQueries.append(query)
        }
        save()
    }

    func deleteSavedQuery(_ id: UUID) {
        savedQueries.removeAll { $0.id == id }
        save()
    }

    // MARK: - Saved Diagrams

    func saveDiagram(_ diagram: SavedDiagram) {
        if let idx = savedDiagrams.firstIndex(where: { $0.id == diagram.id }) {
            savedDiagrams[idx] = diagram
        } else {
            savedDiagrams.append(diagram)
        }
        save()
    }

    func deleteSavedDiagram(_ id: UUID) {
        savedDiagrams.removeAll { $0.id == id }
        save()
    }

    // MARK: - Query History

    func addHistoryEntry(_ entry: QueryHistoryEntry) {
        queryHistory.insert(entry, at: 0)
        if queryHistory.count > 100 {
            queryHistory = Array(queryHistory.prefix(100))
        }
        save()
    }

    func clearHistory() {
        queryHistory.removeAll()
        save()
    }

    func updateAlias(groupId: UUID, memberId: UUID, alias: String) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupId }),
              let mIdx = groups[gIdx].members.firstIndex(where: { $0.id == memberId }) else { return }
        groups[gIdx].members[mIdx].alias = alias
        save()
    }
}
