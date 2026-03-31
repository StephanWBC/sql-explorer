import SwiftUI

struct ObjectExplorerRow: View {
    @ObservedObject var node: DatabaseObject
    @EnvironmentObject var appState: AppState
    @ObservedObject var userDataStore: UserDataStore
    var onConnect: ((DatabaseObject) -> Void)?
    var onDisconnect: ((DatabaseObject) -> Void)?
    var onNewQuery: ((DatabaseObject) -> Void)?
    var onExpand: ((DatabaseObject) -> Void)?

    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @State private var showingAliasPrompt = false
    @State private var aliasText = ""
    @State private var pendingGroupId: UUID?

    var body: some View {
        HStack(spacing: 5) {
            // Connection status dot for databases
            if node.objectType == .database {
                Circle()
                    .fill(node.isConnected ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 7, height: 7)
            }

            // Server status dot — only outside DisclosureGroup context
            // (DisclosureGroup in MainView handles server expand, so skip dot there)

            // Icon
            Image(systemName: node.icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            // Name
            Text(node.name)
                .font(.system(size: 12, weight: isGroupOrServer ? .semibold : .regular))
                .foregroundStyle(node.isConnected || node.objectType == .server ? .primary : .secondary)
                .lineLimit(1)

            // Connecting spinner
            if node.isConnecting {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            }

            Spacer()

            // Star button for databases
            if node.objectType == .database {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(isFavorite ? .yellow : .gray.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
        .padding(.vertical, 1)
        .onAppear {
            if node.objectType == .database && node.isConnected && !node.isLoaded && node.children.isEmpty {
                onExpand?(node)
            }
        }
        .onTapGesture(count: 2) {
            if node.objectType == .database {
                if node.isConnected {
                    onNewQuery?(node)
                } else {
                    onConnect?(node)
                }
            }
        }
        .contextMenu {
            if node.objectType == .database {
                if node.isConnected {
                    Button {
                        onNewQuery?(node)
                    } label: {
                        Label("New Query", systemImage: "plus.rectangle")
                    }

                    Button {
                        onExpand?(node)
                    } label: {
                        Label("Refresh Schema", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button {
                        onDisconnect?(node)
                    } label: {
                        Label("Disconnect", systemImage: "bolt.slash")
                    }
                } else {
                    Button {
                        onConnect?(node)
                    } label: {
                        Label("Connect", systemImage: "bolt.fill")
                    }
                }

                Divider()

                // Favorite toggle
                Button {
                    toggleFavorite()
                } label: {
                    Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: isFavorite ? "star.slash" : "star.fill")
                }

                // Add to group — always available, with "New Group" option
                Menu("Add to Group") {
                    ForEach(userDataStore.groups) { group in
                        Button(group.name) {
                            pendingGroupId = group.id
                            aliasText = node.name
                            showingAliasPrompt = true
                        }
                    }
                    if !userDataStore.groups.isEmpty { Divider() }
                    Button("New Group...") {
                        showingNewGroup = true
                    }
                }
            }
        }
        .alert("New Group", isPresented: $showingNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Create") {
                let name = newGroupName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let group = userDataStore.addGroup(name: name)
                pendingGroupId = group.id
                aliasText = node.name
                newGroupName = ""
                // Show alias prompt next
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingAliasPrompt = true
                }
            }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("Create a new group and add \(node.name) to it.")
        }
        .alert("Alias", isPresented: $showingAliasPrompt) {
            TextField("Alias (e.g. BLMS Dev)", text: $aliasText)
            Button("Add") {
                guard let groupId = pendingGroupId else { return }
                addToGroupWithAlias(groupId: groupId, alias: aliasText)
                aliasText = ""
                pendingGroupId = nil
            }
            Button("Cancel", role: .cancel) {
                aliasText = ""
                pendingGroupId = nil
            }
        } message: {
            Text("Give \(node.name) an alias in this group (optional).")
        }
    }

    private var isFavorite: Bool {
        guard let fqdn = node.serverFqdn ?? findServerFqdn() else { return false }
        return userDataStore.isFavorite(databaseName: node.name, serverFqdn: fqdn)
    }

    private func toggleFavorite() {
        guard let fqdn = node.serverFqdn ?? findServerFqdn() else { return }
        let sub = appState.authService.selectedSubscription
        userDataStore.toggleFavorite(
            databaseName: node.name, serverFqdn: fqdn,
            subscriptionId: sub?.id ?? "", subscriptionName: sub?.name ?? "")
    }

    private func addToGroup(_ group: DatabaseGroup) {
        addToGroupWithAlias(groupId: group.id, alias: node.name)
    }

    private func addToGroupWithAlias(groupId: UUID, alias: String) {
        guard let fqdn = node.serverFqdn ?? findServerFqdn() else { return }
        let sub = appState.authService.selectedSubscription
        let finalAlias = alias.trimmingCharacters(in: .whitespaces).isEmpty ? node.name : alias.trimmingCharacters(in: .whitespaces)
        userDataStore.addToGroup(
            groupId: groupId, databaseName: node.name, serverFqdn: fqdn,
            subscriptionId: sub?.id ?? "", subscriptionName: sub?.name ?? "",
            alias: finalAlias)
    }

    private func findServerFqdn() -> String? {
        for server in appState.explorerNodes {
            if server.children.contains(where: { $0.id == node.id }) {
                return server.name + ".database.windows.net"
            }
        }
        return nil
    }

    private var hasConnectedChild: Bool {
        node.children.contains { $0.isConnected }
    }

    private var isGroupOrServer: Bool {
        node.objectType == .connectionGroup || node.objectType == .server
    }

    private var iconColor: Color {
        switch node.objectType {
        case .server: return .blue
        case .connectionGroup: return .orange
        case .database: return node.isConnected ? .green : .secondary
        case .table: return .green
        case .view: return .teal
        case .storedProcedure: return .orange
        case .function: return .pink
        case .primaryKey: return .yellow
        case .foreignKey: return .cyan
        default: return .secondary
        }
    }
}
