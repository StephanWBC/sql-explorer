import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var userDataStore: UserDataStore
    @Binding var selectedSidebarTab: SidebarTab
    @State private var expandedNodes: Set<UUID> = []
    @State private var favoriteToRemove: FavoriteDatabase?

    var body: some View {
        if userDataStore.favorites.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "star")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("No favorites yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Click the ☆ icon next to a database")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(userDataStore.favorites) { fav in
                let connected = appState.isConnected(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn)
                let dbNode = connected ? appState.findConnectedNode(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn) : nil

                if let db = dbNode, db.isExpandable && !db.children.isEmpty {
                    // Connected with schema — show expandable tree
                    DisclosureGroup(isExpanded: expandedBinding(db.id)) {
                        ForEach(db.children) { folder in
                            if folder.isExpandable && !folder.children.isEmpty {
                                DisclosureGroup(isExpanded: expandedBinding(folder.id)) {
                                    ForEach(folder.children) { item in
                                        if item.isExpandable {
                                            DisclosureGroup(isExpanded: expandedBinding(item.id)) {
                                                ForEach(item.children) { col in
                                                    schemaRow(col)
                                                }
                                            } label: {
                                                schemaRow(item)
                                            }
                                        } else {
                                            schemaRow(item)
                                        }
                                    }
                                } label: {
                                    schemaRow(folder)
                                }
                            } else {
                                schemaRow(folder)
                            }
                        }
                    } label: {
                        connectedFavoriteLabel(fav, db: db)
                    }
                } else {
                    // Not connected — flat row
                    FavoriteRow(favorite: fav, appState: appState)
                        .contextMenu { favoriteContextMenu(fav, connected: connected) }
                        .onTapGesture(count: 2) {
                            if connected {
                                appState.newQueryForFavorite(fav)
                            } else {
                                Task { await appState.connectToFavorite(fav) }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .confirmationDialog(
                "Remove Favorite",
                isPresented: Binding(
                    get: { favoriteToRemove != nil },
                    set: { if !$0 { favoriteToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let fav = favoriteToRemove {
                        userDataStore.removeFavorite(fav.id)
                    }
                    favoriteToRemove = nil
                }
                Button("Cancel", role: .cancel) { favoriteToRemove = nil }
            } message: {
                Text("Remove \"\(favoriteToRemove?.displayName ?? "")\" from favorites?")
            }
        }
    }

    // MARK: - Connected favorite label (like Connected section in Explorer)

    @ViewBuilder
    private func connectedFavoriteLabel(_ fav: FavoriteDatabase, db: DatabaseObject) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(fav.displayName)
                        .font(.system(size: 12, weight: .medium))
                    SubscriptionPill(favorite: fav, appState: appState)
                }
                Text(fav.shortServer)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .contextMenu { favoriteContextMenu(fav, connected: true) }
        .onTapGesture(count: 2) {
            appState.newQueryForFavorite(fav)
        }
    }

    // MARK: - Schema tree row (folders and leaves)

    @ViewBuilder
    private func schemaRow(_ node: DatabaseObject) -> some View {
        ObjectExplorerRow(
            node: node,
            userDataStore: appState.userDataStore,
            onConnect: { db in Task { await appState.connectToDatabase(db) } },
            onDisconnect: { db in appState.disconnectFromDatabase(db) },
            onNewQuery: { db in appState.newQueryForDatabase(db) },
            onExpand: { obj in
                if obj.objectType == .table || obj.objectType == .view {
                    Task { await appState.loadColumnsForTable(obj) }
                } else {
                    obj.isLoaded = false
                    Task { await appState.loadSchemaForDatabase(obj) }
                }
            }
        )
    }

    // MARK: - Context menu (shared between flat and tree modes)

    @ViewBuilder
    private func favoriteContextMenu(_ fav: FavoriteDatabase, connected: Bool) -> some View {
        if connected {
            Button {
                appState.newQueryForFavorite(fav)
            } label: {
                Label("New Query", systemImage: "plus.rectangle")
            }

            if let connId = appState.connectionId(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn) {
                Button {
                    Task { await appState.openERDPicker(databaseName: fav.databaseName, connectionId: connId) }
                    openWindow(id: "erd")
                } label: {
                    Label("Database Diagram", systemImage: "rectangle.connected.to.line.below")
                }
            }

            Divider()

            Button {
                appState.disconnect(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash")
            }
        } else {
            Button {
                Task { await appState.connectToFavorite(fav) }
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
        }

        Divider()

        Button {
            selectedSidebarTab = .explorer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                appState.revealInExplorer(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn)
            }
        } label: {
            Label("Show in Explorer", systemImage: "sidebar.left")
        }

        Divider()

        if !userDataStore.groups.isEmpty {
            Menu("Add to Group") {
                ForEach(userDataStore.groups) { group in
                    Button(group.name) {
                        userDataStore.addToGroup(
                            groupId: group.id,
                            databaseName: fav.databaseName, serverFqdn: fav.serverFqdn,
                            subscriptionId: fav.subscriptionId, subscriptionName: fav.subscriptionName,
                            alias: fav.displayName)
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            favoriteToRemove = fav
        } label: {
            Label("Remove from Favorites", systemImage: "star.slash")
        }
    }

    // MARK: - Expansion binding

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedNodes.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedNodes.insert(id) }
                else { expandedNodes.remove(id) }
            }
        )
    }
}

struct FavoriteRow: View {
    let favorite: FavoriteDatabase
    @ObservedObject var appState: AppState

    private var connected: Bool {
        appState.isConnected(databaseName: favorite.databaseName, serverFqdn: favorite.serverFqdn)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.red.opacity(0.6))
                .frame(width: 7, height: 7)

            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(favorite.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(connected ? .primary : .secondary)
                    SubscriptionPill(favorite: favorite, appState: appState)
                }
                Text("\(favorite.shortServer)  ·  \(favorite.subscriptionName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
