import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var userDataStore: UserDataStore
    @Binding var selectedSidebarTab: SidebarTab
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var editingAlias: UUID?
    @State private var aliasText = ""

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
                                GroupMemberRow(member: member, appState: appState)
                                    .contextMenu {
                                        let connected = appState.isConnected(
                                            databaseName: member.databaseName, serverFqdn: member.serverFqdn)

                                        if connected {
                                            Button {
                                                appState.newQueryForGroupMember(member)
                                            } label: {
                                                Label("New Query", systemImage: "plus.rectangle")
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
                                            appState.revealInExplorer(databaseName: member.databaseName, serverFqdn: member.serverFqdn)
                                            selectedSidebarTab = .explorer
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
                                    .onTapGesture(count: 2) {
                                        let connected = appState.isConnected(
                                            databaseName: member.databaseName, serverFqdn: member.serverFqdn)
                                        if connected {
                                            appState.newQueryForGroupMember(member)
                                        } else {
                                            Task { await appState.connectToGroupMember(member) }
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
}

struct GroupMemberRow: View {
    let member: GroupMember
    @ObservedObject var appState: AppState

    private var connected: Bool {
        appState.isConnected(databaseName: member.databaseName, serverFqdn: member.serverFqdn)
    }

    var body: some View {
        HStack(spacing: 6) {
            // REAL connection status — green if connected, red if not
            Circle()
                .fill(connected ? Color.green : Color.red.opacity(0.6))
                .frame(width: 7, height: 7)

            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(connected ? .green : .purple)

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
