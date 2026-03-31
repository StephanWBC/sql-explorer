import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var userDataStore: UserDataStore
    @Binding var selectedSidebarTab: SidebarTab

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
                FavoriteRow(favorite: fav, appState: appState)
                    .contextMenu {
                        if appState.isConnected(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn) {
                            Button {
                                appState.newQueryForFavorite(fav)
                            } label: {
                                Label("New Query", systemImage: "plus.rectangle")
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
                            userDataStore.removeFavorite(fav.id)
                        } label: {
                            Label("Remove from Favorites", systemImage: "star.slash")
                        }
                    }
                    .onTapGesture(count: 2) {
                        if appState.isConnected(databaseName: fav.databaseName, serverFqdn: fav.serverFqdn) {
                            appState.newQueryForFavorite(fav)
                        } else {
                            Task { await appState.connectToFavorite(fav) }
                        }
                    }
            }
            .listStyle(.sidebar)
        }
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
            // Connection status dot
            Circle()
                .fill(connected ? Color.green : Color.red.opacity(0.6))
                .frame(width: 7, height: 7)

            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(connected ? .primary : .secondary)
                Text("\(favorite.shortServer)  ·  \(favorite.subscriptionName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
