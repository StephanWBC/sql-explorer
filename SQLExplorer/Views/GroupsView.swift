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
    @State private var groupToDelete: DatabaseGroup?
    @State private var memberToRemoveGroupId: UUID?
    @State private var memberToRemove: GroupMember?

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
                                    groupToDelete = group
                                } label: {
                                    Label("Delete Group", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .confirmationDialog(
                    "Delete Group",
                    isPresented: Binding(
                        get: { groupToDelete != nil },
                        set: { if !$0 { groupToDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let g = groupToDelete { userDataStore.removeGroup(g.id) }
                        groupToDelete = nil
                    }
                    Button("Cancel", role: .cancel) { groupToDelete = nil }
                } message: {
                    Text("Delete group \"\(groupToDelete?.name ?? "")\" and all its members? This cannot be undone.")
                }
                .confirmationDialog(
                    "Remove from Group",
                    isPresented: Binding(
                        get: { memberToRemove != nil },
                        set: { if !$0 { memberToRemove = nil; memberToRemoveGroupId = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        if let groupId = memberToRemoveGroupId, let member = memberToRemove {
                            userDataStore.removeFromGroup(groupId: groupId, memberId: member.id)
                        }
                        memberToRemove = nil
                        memberToRemoveGroupId = nil
                    }
                    Button("Cancel", role: .cancel) { memberToRemove = nil; memberToRemoveGroupId = nil }
                } message: {
                    Text("Remove \"\(memberToRemove?.alias ?? "")\" from this group?")
                }
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
                HStack(spacing: 5) {
                    Text(member.alias)
                        .font(.system(size: 12, weight: .medium))
                    SubscriptionPill(member: member, appState: appState)
                }
                Text("\(member.databaseName)  ·  \(member.shortServer)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            favoriteStarButton(member)
        }
        .contextMenu { memberContextMenu(member, group: group, connected: true) }
        .onTapGesture(count: 2) {
            appState.newQueryForGroupMember(member)
        }
    }

    // MARK: - Favorite star (inline)

    @ViewBuilder
    private func favoriteStarButton(_ member: GroupMember) -> some View {
        let isFav = appState.userDataStore.isFavorite(
            databaseName: member.databaseName, serverFqdn: member.serverFqdn)
        Button {
            appState.userDataStore.toggleFavorite(descriptor: descriptor(for: member))
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(.system(size: 10))
                .foregroundStyle(isFav ? .yellow : .gray.opacity(0.3))
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
    }

    private func descriptor(for member: GroupMember) -> ConnectionDescriptor {
        ConnectionDescriptor(
            kind: member.kind,
            databaseName: member.databaseName, serverFqdn: member.serverFqdn,
            alias: member.alias,
            subscriptionId: member.subscriptionId, subscriptionName: member.subscriptionName,
            port: member.port, username: member.username,
            keychainRef: member.keychainRef,
            encrypt: member.encrypt, trustServerCertificate: member.trustServerCertificate)
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

            Button {
                if let node = appState.findConnectedNode(
                    databaseName: member.databaseName, serverFqdn: member.serverFqdn) {
                    node.isLoaded = false
                    Task { await appState.loadSchemaForDatabase(node) }
                }
            } label: {
                Label("Refresh Schema", systemImage: "arrow.clockwise")
            }

            if let connId = appState.connectionId(databaseName: member.databaseName, serverFqdn: member.serverFqdn) {
                Button {
                    Task { await appState.openERDPicker(databaseName: member.databaseName, connectionId: connId) }
                    openWindow(id: "erd")
                } label: {
                    Label("Database Diagram", systemImage: "rectangle.connected.to.line.below")
                }
            }

            if let node = appState.findConnectedNode(
                databaseName: member.databaseName, serverFqdn: member.serverFqdn) {
                Button {
                    if appState.openPerformanceMonitor(for: node) {
                        openWindow(id: "performance")
                    }
                } label: {
                    Label("Performance", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(!appState.canOpenPerformanceMonitor(for: node))
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

        // Favorite toggle (parity with Object Explorer)
        let isFav = appState.userDataStore.isFavorite(
            databaseName: member.databaseName, serverFqdn: member.serverFqdn)
        Button {
            appState.userDataStore.toggleFavorite(descriptor: descriptor(for: member))
        } label: {
            Label(isFav ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: isFav ? "star.slash" : "star.fill")
        }

        // Add to another group — preserves kind/keychainRef/etc. across groups.
        let otherGroups = appState.userDataStore.groups.filter { $0.id != group.id }
        if !otherGroups.isEmpty {
            Menu("Add to Group") {
                ForEach(otherGroups) { g in
                    Button(g.name) {
                        appState.userDataStore.addToGroup(groupId: g.id, descriptor: descriptor(for: member))
                    }
                }
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
            memberToRemoveGroupId = group.id
            memberToRemove = member
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

    private var isFavorite: Bool {
        appState.userDataStore.isFavorite(
            databaseName: member.databaseName, serverFqdn: member.serverFqdn)
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
                HStack(spacing: 5) {
                    Text(member.alias)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(connected ? .primary : .secondary)
                    SubscriptionPill(member: member, appState: appState)
                }
                Text("\(member.databaseName)  ·  \(member.shortServer)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                appState.userDataStore.toggleFavorite(descriptor: ConnectionDescriptor(
                    kind: member.kind,
                    databaseName: member.databaseName, serverFqdn: member.serverFqdn,
                    alias: member.alias,
                    subscriptionId: member.subscriptionId, subscriptionName: member.subscriptionName,
                    port: member.port, username: member.username,
                    keychainRef: member.keychainRef,
                    encrypt: member.encrypt, trustServerCertificate: member.trustServerCertificate))
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(isFavorite ? .yellow : .gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 1)
    }
}

/// Small pill shown beside a Group/Favorite member's alias.
/// - Azure-kind member from a *different* subscription than the active picker → orange
///   subscription-name pill (helps distinguish cross-subscription entries).
/// - Manual-kind member (no Azure subscription at all) → purple "Manual" pill.
/// - Azure member matching the active subscription → no pill.
struct SubscriptionPill: View {
    let kind: ConnectionKind
    let subscriptionId: String?
    let subscriptionName: String?
    @ObservedObject var appState: AppState

    init(kind: ConnectionKind, subscriptionId: String?, subscriptionName: String?, appState: AppState) {
        self.kind = kind
        self.subscriptionId = subscriptionId
        self.subscriptionName = subscriptionName
        self.appState = appState
    }

    init(member: GroupMember, appState: AppState) {
        self.init(
            kind: member.kind,
            subscriptionId: member.subscriptionId,
            subscriptionName: member.subscriptionName,
            appState: appState)
    }

    init(favorite: FavoriteDatabase, appState: AppState) {
        self.init(
            kind: favorite.kind,
            subscriptionId: favorite.subscriptionId,
            subscriptionName: favorite.subscriptionName,
            appState: appState)
    }

    private var isForeignAzure: Bool {
        guard kind == .azureEntra,
              let id = subscriptionId, !id.isEmpty else { return false }
        // No active subscription → treat any tagged azure member as "foreign" so the
        // user still sees which subscription it belongs to.
        guard let active = appState.authService.selectedSubscription else { return true }
        return id != active.id
    }

    var body: some View {
        Group {
            if kind != .azureEntra {
                Text("Manual")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(Color.purple.opacity(0.4), lineWidth: 0.5))
                    .help(kind == .manualSqlAuth
                          ? "Manual SQL authentication (credentials in Keychain)"
                          : "Manual server with Microsoft Entra ID")
            } else if isForeignAzure, let name = subscriptionName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
                    .help("This database is in the \(name) subscription")
            }
        }
    }
}
