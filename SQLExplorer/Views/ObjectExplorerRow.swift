import SwiftUI

struct ObjectExplorerRow: View {
    @ObservedObject var node: DatabaseObject
    @EnvironmentObject var appState: AppState
    @ObservedObject var userDataStore: UserDataStore
    var onConnect: ((DatabaseObject) -> Void)?
    var onDisconnect: ((DatabaseObject) -> Void)?
    var onNewQuery: ((DatabaseObject) -> Void)?
    var onExpand: ((DatabaseObject) -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            // Connection status dot for databases
            if node.objectType == .database {
                Circle()
                    .fill(node.isConnected ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 7, height: 7)
            }

            // Server status dot
            if node.objectType == .server {
                Circle()
                    .fill(hasConnectedChild ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 7, height: 7)
            }

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

                // Add to group submenu
                if !userDataStore.groups.isEmpty {
                    Menu("Add to Group") {
                        ForEach(userDataStore.groups) { group in
                            Button(group.name) {
                                addToGroup(group)
                            }
                        }
                    }
                }
            }
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
        guard let fqdn = node.serverFqdn ?? findServerFqdn() else { return }
        let sub = appState.authService.selectedSubscription
        userDataStore.addToGroup(
            groupId: group.id, databaseName: node.name, serverFqdn: fqdn,
            subscriptionId: sub?.id ?? "", subscriptionName: sub?.name ?? "",
            alias: node.name)
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
        case .database: return node.isConnected ? .green : .purple
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
