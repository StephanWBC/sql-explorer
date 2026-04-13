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
        // Backwards-compat shim — Azure-only path.
        toggleFavorite(descriptor: ConnectionDescriptor(
            kind: .azureEntra, databaseName: databaseName, serverFqdn: serverFqdn,
            alias: databaseName, subscriptionId: subscriptionId, subscriptionName: subscriptionName))
    }

    /// Toggle favorite status using a full descriptor — supports manual connections
    /// (no subscription) alongside Azure-discovered ones.
    func toggleFavorite(descriptor d: ConnectionDescriptor) {
        if let idx = favorites.firstIndex(where: { $0.databaseName == d.databaseName && $0.serverFqdn == d.serverFqdn }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(FavoriteDatabase(
                databaseName: d.databaseName, serverFqdn: d.serverFqdn,
                subscriptionId: d.subscriptionId, subscriptionName: d.subscriptionName,
                alias: d.alias == d.databaseName ? nil : d.alias,
                kind: d.kind, port: d.port, username: d.username,
                keychainRef: d.keychainRef, encrypt: d.encrypt,
                trustServerCertificate: d.trustServerCertificate))
        }
        save()
    }

    func removeFavorite(_ id: UUID) {
        if let fav = favorites.first(where: { $0.id == id }), let ref = fav.keychainRef {
            KeychainHelper.deletePassword(ref: ref)
        }
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
        // Backwards-compat shim — Azure path.
        addToGroup(groupId: groupId, descriptor: ConnectionDescriptor(
            kind: .azureEntra, databaseName: databaseName, serverFqdn: serverFqdn,
            alias: alias, subscriptionId: subscriptionId, subscriptionName: subscriptionName))
    }

    /// Add a connection (Azure or manual) to a group using a full descriptor.
    func addToGroup(groupId: UUID, descriptor d: ConnectionDescriptor) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        if groups[idx].members.contains(where: { $0.databaseName == d.databaseName && $0.serverFqdn == d.serverFqdn }) { return }
        groups[idx].members.append(GroupMember(
            databaseName: d.databaseName, serverFqdn: d.serverFqdn,
            subscriptionId: d.subscriptionId, subscriptionName: d.subscriptionName,
            alias: d.alias, kind: d.kind, port: d.port, username: d.username,
            keychainRef: d.keychainRef, encrypt: d.encrypt,
            trustServerCertificate: d.trustServerCertificate))
        save()
    }

    func removeFromGroup(groupId: UUID, memberId: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        // Only remove the Keychain entry if no OTHER group/favorite still references
        // this credential — manual connections may be saved in multiple places.
        if let member = groups[idx].members.first(where: { $0.id == memberId }),
           let ref = member.keychainRef,
           !isKeychainRefInUse(ref, excludingGroupMemberId: memberId) {
            KeychainHelper.deletePassword(ref: ref)
        }
        groups[idx].members.removeAll { $0.id == memberId }
        save()
    }

    private func isKeychainRefInUse(_ ref: String, excludingGroupMemberId: UUID? = nil, excludingFavoriteId: UUID? = nil) -> Bool {
        for g in groups {
            for m in g.members where m.keychainRef == ref && m.id != excludingGroupMemberId {
                return true
            }
        }
        for f in favorites where f.keychainRef == ref && f.id != excludingFavoriteId {
            return true
        }
        return false
    }

    // MARK: - Subscription normalization (badge bug fix)

    /// Walks every Azure-kind member/favorite and rewrites stale subscriptionId/Name
    /// using the cross-subscription server lookup. Existing user data was tagged with
    /// "whichever subscription happened to be selected when the row was added", which
    /// makes the cross-subscription pill render incorrectly when those don't match.
    /// Call this whenever `serverToSubscription` changes.
    func normalizeAzureSubscriptions(using map: [String: AzureSubscription]) {
        guard !map.isEmpty else { return }
        var changed = false

        for gIdx in groups.indices {
            for mIdx in groups[gIdx].members.indices {
                let m = groups[gIdx].members[mIdx]
                guard m.kind == .azureEntra, let sub = map[m.serverFqdn] else { continue }
                if m.subscriptionId != sub.id || m.subscriptionName != sub.name {
                    groups[gIdx].members[mIdx].subscriptionId = sub.id
                    groups[gIdx].members[mIdx].subscriptionName = sub.name
                    changed = true
                }
            }
        }
        for fIdx in favorites.indices {
            let f = favorites[fIdx]
            guard f.kind == .azureEntra, let sub = map[f.serverFqdn] else { continue }
            if f.subscriptionId != sub.id || f.subscriptionName != sub.name {
                favorites[fIdx].subscriptionId = sub.id
                favorites[fIdx].subscriptionName = sub.name
                changed = true
            }
        }

        if changed { save() }
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
