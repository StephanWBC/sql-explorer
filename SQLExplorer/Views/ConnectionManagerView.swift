import SwiftUI

struct ConnectionManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var selectedConnection: SavedConnection?
    @State private var selectedGroup: ConnectionGroup?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Connections")
                    .font(.headline)
                Spacer()
                Button("+ Group") {
                    let group = ConnectionGroup(name: "New Group")
                    appState.connectionStore.saveGroup(group)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            HSplitView {
                // Left: Groups + connections tree
                List {
                    ForEach(appState.connectionStore.groups) { group in
                        Section(group.name) {
                            ForEach(appState.connectionStore.connectionsForGroup(group.id)) { conn in
                                ConnectionRow(connection: conn, isSelected: selectedConnection?.id == conn.id)
                                    .onTapGesture { selectedConnection = conn; selectedGroup = group }
                            }
                        }
                    }

                    let ungrouped = appState.connectionStore.ungroupedConnections()
                    if !ungrouped.isEmpty {
                        Section("Ungrouped") {
                            ForEach(ungrouped) { conn in
                                ConnectionRow(connection: conn, isSelected: selectedConnection?.id == conn.id)
                                    .onTapGesture { selectedConnection = conn; selectedGroup = nil }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 250)

                // Right: Actions
                VStack(alignment: .leading, spacing: 16) {
                    if let conn = selectedConnection {
                        GroupBox("Selected: \(conn.name)") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Server: \(conn.server)")
                                    .font(.caption)
                                Text("Database: \(conn.database)")
                                    .font(.caption)
                                if let env = conn.environmentLabel {
                                    HStack {
                                        Text("Environment:")
                                            .font(.caption)
                                        Text(env)
                                            .font(.caption.bold())
                                            .foregroundStyle(EnvironmentLabel.from(env)?.color ?? .secondary)
                                    }
                                }
                            }
                            .padding(4)
                        }

                        GroupBox("Actions") {
                            VStack(alignment: .leading, spacing: 6) {
                                Button("Delete Connection", role: .destructive) {
                                    showDeleteConfirmation = true
                                }

                                Divider()

                                Text("Move to Group:")
                                    .font(.caption.bold())
                                ForEach(appState.connectionStore.groups) { group in
                                    Button(group.name) {
                                        moveConnection(conn, to: group.id)
                                    }
                                    .disabled(conn.groupId == group.id)
                                }
                                Button("Ungrouped") {
                                    moveConnection(conn, to: nil)
                                }
                                .disabled(conn.groupId == nil)
                            }
                            .padding(4)
                        }
                    } else {
                        Text("Select a connection to manage")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Spacer()
                }
                .padding()
                .frame(minWidth: 250)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .confirmationDialog(
            "Delete Connection",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let conn = selectedConnection {
                    appState.connectionStore.deleteConnection(conn.id)
                    selectedConnection = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(selectedConnection?.name ?? "")\"? This cannot be undone.")
        }
    }

    private func moveConnection(_ conn: SavedConnection, to groupId: UUID?) {
        var updated = conn
        updated.groupId = groupId
        appState.connectionStore.saveConnection(updated)
        selectedConnection = updated
    }
}

struct ConnectionRow: View {
    let connection: SavedConnection
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 12, weight: .medium))
                Text("\(connection.server) / \(connection.database)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let env = connection.environmentLabel {
                Text(env)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(EnvironmentLabel.from(env)?.color ?? .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(EnvironmentLabel.from(env)?.badgeBackground ?? Color.clear)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
}
