import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var userDataStore: UserDataStore

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
                Text("Right-click a database → Add to Favorites")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(userDataStore.favorites) { fav in
                FavoriteRow(favorite: fav)
                    .contextMenu {
                        Button {
                            Task { await connectFavorite(fav) }
                        } label: {
                            Label("Connect", systemImage: "bolt.fill")
                        }

                        Button {
                            appState.newQueryForFavorite(fav)
                        } label: {
                            Label("New Query", systemImage: "plus.rectangle")
                        }

                        Divider()

                        ForEach(userDataStore.groups) { group in
                            Button("Add to \(group.name)") {
                                userDataStore.addToGroup(
                                    groupId: group.id,
                                    databaseName: fav.databaseName,
                                    serverFqdn: fav.serverFqdn,
                                    subscriptionId: fav.subscriptionId,
                                    subscriptionName: fav.subscriptionName,
                                    alias: fav.displayName)
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
                        Task { await connectFavorite(fav) }
                    }
            }
            .listStyle(.sidebar)
        }
    }

    private func connectFavorite(_ fav: FavoriteDatabase) async {
        // Find or create a database node and connect
        await appState.connectToFavorite(fav)
    }
}

struct FavoriteRow: View {
    let favorite: FavoriteDatabase

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.displayName)
                    .font(.system(size: 12, weight: .medium))
                Text("\(favorite.shortServer)  ·  \(favorite.subscriptionName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
