import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var userDataStore: UserDataStore
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
                        if !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty {
                            _ = userDataStore.addGroup(name: newGroupName.trimmingCharacters(in: .whitespaces))
                            newGroupName = ""
                            isCreatingGroup = false
                        }
                    }
                    .controlSize(.small)
                    Button("Cancel") {
                        isCreatingGroup = false
                        newGroupName = ""
                    }
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
                    Text("Create a group, then add databases from Explorer")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(userDataStore.groups) { group in
                        Section {
                            ForEach(group.members) { member in
                                GroupMemberRow(member: member, editingAlias: $editingAlias, aliasText: $aliasText)
                                    .contextMenu {
                                        Button {
                                            Task { await appState.connectToGroupMember(member) }
                                        } label: {
                                            Label("Connect", systemImage: "bolt.fill")
                                        }

                                        Button {
                                            appState.newQueryForGroupMember(member)
                                        } label: {
                                            Label("New Query", systemImage: "plus.rectangle")
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
                                        Task { await appState.connectToGroupMember(member) }
                                    }

                                // Inline alias editor
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
    @Binding var editingAlias: UUID?
    @Binding var aliasText: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red.opacity(0.6))
                .frame(width: 7, height: 7)

            Image(systemName: "cylinder")
                .font(.system(size: 11))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 1) {
                Text(member.alias)
                    .font(.system(size: 12, weight: .medium))
                Text("\(member.databaseName)  ·  \(member.shortServer)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}
