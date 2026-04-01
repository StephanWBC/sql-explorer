import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var userDataStore: UserDataStore
    @Binding var selectedSidebarTab: SidebarTab
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var editingAlias: UUID?
    @State private var aliasText = ""
    @State private var expandedNodes: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Create group bar
            HStack {
                if isCreatingGroup {
                    TextField("Group name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("Create") {
                        let name = newGroupName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            _ = userDataStore.addGroup(name: name)
                            newGroupName = ""
                            isCreatingGroup = false
                        }
                    }
                    .controlSize(.small)
                    Button("Cancel") { isCreatingGroup = false; newGroupName = "" }
                        .controlSize(.small)
                } else {
                    Spacer()
                    Button {
                        isCreatingGroup = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if userDataStore.groups.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No groups yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(userDataStore.groups) { group in
                        Section {
                            ForEach(group.members) { member in
                                let connected = appState.isConnected(
                                    databaseName: member.databaseName, serverFqdn: member.serverFqdn)
                                let dbNode = connected ? appState.findConnectedNode(databaseName: member.databaseName, serverFqdn: member.serverFqdn) : nil

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
                                        connectedMemberLabel(member, group: group)
                                    }
                                } else {
                                    // Not connected — flat row
                                    GroupMemberRow(member: member, appState: appState)
                                        .contextMenu { memberContextMenu(member, group: group, connected: connected) }
                                        .onTapGesture(count: 2) {
                                            if connected {
                                                appState.newQueryForGroupMember(member)
                                            } else {
                                                Task { await appState.connectToGroupMember(member) }
                                            }
                                        }
                                }

                                if editingAlias == member.id {
                                    HStack {
                                        TextField("Alias", text: $aliasText)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11))
                                        Button("Save") {
                                            userDataStore.updateAlias(groupId: group.id, memberId: member.id, alias: aliasText)
                                            editingAlias = nil
                                        }
                                        .controlSize(.small)
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                        } header: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 11))
                                Text(group.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("(\(group.members.count))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    userDataStore.removeGroup(group.id)
                                } label: {
                                    Label("Delete Group", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Connected member label (like Connected section in Explorer)

    @ViewBuilder
    private func connectedMemberLabel(_ member: GroupMember, group: DatabaseGroup) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.alias)
                    .font(.system(size: 12, weight: .medium))
                Text("\(member.databaseName)  ·  \(member.shortServer)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .contextMenu { memberContextMenu(member, group: group, connected: true) }
        .onTapGesture(count: 2) {
            appState.newQueryForGroupMember(member)
        }
    }

    // MARK: - Schema tree row

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

    // MARK: - Context menu

    @ViewBuilder
    private func memberContextMenu(_ member: GroupMember, group: DatabaseGroup, connected: Bool) -> some View {
        if connected {
            Button {
                appState.newQueryForGroupMember(member)
            } label: {
                Label("New Query", systemImage: "plus.rectangle")
            }

            if let connId = appState.connectionId(databaseName: member.databaseName, serverFqdn: member.serverFqdn) {
                Button {
                    Task { await appState.loadERD(databaseName: member.databaseName, connectionId: connId) }
                    openWindow(id: "erd")
                } label: {
                    Label("Database Diagram", systemImage: "rectangle.connected.to.line.below")
                }
            }

            Divider()

            Button {
                appState.disconnect(databaseName: member.databaseName, serverFqdn: member.serverFqdn)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash")
            }
        } else {
            Button {
                Task { await appState.connectToGroupMember(member) }
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
        }

        Divider()

        Button {
            selectedSidebarTab = .explorer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                appState.revealInExplorer(databaseName: member.databaseName, serverFqdn: member.serverFqdn)
            }
        } label: {
            Label("Show in Explorer", systemImage: "sidebar.left")
        }

        Divider()

        Button("Edit Alias") {
            aliasText = member.alias
            editingAlias = member.id
        }

        Button(role: .destructive) {
            userDataStore.removeFromGroup(groupId: group.id, memberId: member.id)
        } label: {
            Label("Remove from Group", systemImage: "minus.circle")
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

struct GroupMemberRow: View {
    let member: GroupMember
    @ObservedObject var appState: AppState

    private var connected: Bool {
        appState.isConnected(databaseName: member.databaseName, serverFqdn: member.serverFqdn)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.red.opacity(0.6))
                .frame(width: 7, height: 7)

            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(connected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(member.alias)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(connected ? .primary : .secondary)
                Text("\(member.databaseName)  ·  \(member.shortServer)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}
