import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var selectedDatabase: AzureDatabase?
    @State private var connectionName = ""
    @State private var selectedGroup: ConnectionGroup?
    @State private var environmentLabel: EnvironmentLabel?
    @State private var customEnvironment = ""
    @State private var trustCert = true
    @State private var encrypt = true
    @State private var saveConnection = true

    @State private var isConnecting = false
    @State private var statusMessage = ""
    @State private var isError = false

    // Group editing
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""

    // Manual server entry (for SQL Auth fallback)
    @State private var manualMode = false
    @State private var server = ""
    @State private var port = "1433"
    @State private var database = "master"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cylinder.split.1x2")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Connect to Database")
                        .font(.headline)
                    if authService.isSignedIn {
                        Text(authService.userEmail)
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Sign in from the sidebar first")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()

                // Toggle manual mode
                Toggle("Manual", isOn: $manualMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Switch to manual server entry")
            }
            .padding()

            Divider()

            Form {
                if manualMode {
                    // Manual SQL Auth
                    Section("Server") {
                        TextField("Server", text: $server, prompt: Text("myserver.database.windows.net"))
                        TextField("Port", text: $port)
                        TextField("Database", text: $database, prompt: Text("master"))
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                    }
                } else if !authService.isSignedIn {
                    // Not signed in — prompt
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("Sign in to discover your Azure SQL databases")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Text("Use the Sign In button in the sidebar")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    // Signed in — show subscription + database picker
                    Section("Subscription") {
                        Picker("Subscription", selection: Binding(
                            get: { authService.selectedSubscription },
                            set: { sub in
                                authService.selectedSubscription = sub
                                if let sub {
                                    Task {
                                        await authService.discoverDatabases(
                                            subscriptionId: sub.id, subscriptionName: sub.name)
                                    }
                                }
                            }
                        )) {
                            ForEach(authService.subscriptions) { sub in
                                Text(sub.name).tag(sub as AzureSubscription?)
                            }
                        }

                        if authService.isLoadingSubscriptions {
                            ProgressView("Loading subscriptions...")
                                .font(.caption)
                        }
                    }

                    Section("Database") {
                        if authService.isLoadingDatabases {
                            ProgressView("Discovering databases...")
                                .font(.caption)
                        } else if authService.databases.isEmpty {
                            Text("No databases found in this subscription")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Database", selection: $selectedDatabase) {
                                Text("Select a database").tag(nil as AzureDatabase?)
                                ForEach(authService.databases) { db in
                                    VStack(alignment: .leading) {
                                        Text(db.databaseName)
                                        Text(db.serverFqdn)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(db as AzureDatabase?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                // Group
                Section("Group") {
                    HStack {
                        Picker("Group", selection: $selectedGroup) {
                            Text("No group").tag(nil as ConnectionGroup?)
                            ForEach(appState.connectionStore.groups) { group in
                                Text(group.name).tag(group as ConnectionGroup?)
                            }
                        }
                        Button(action: {
                            newGroupName = ""
                            isCreatingGroup = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }

                if isCreatingGroup {
                    Section("New Group") {
                        TextField("Enter group name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Spacer()
                            Button("Cancel") {
                                isCreatingGroup = false
                                newGroupName = ""
                            }
                            Button("Create") {
                                guard !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                let group = ConnectionGroup(name: newGroupName.trimmingCharacters(in: .whitespaces))
                                appState.connectionStore.saveGroup(group)
                                selectedGroup = group
                                isCreatingGroup = false
                                newGroupName = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                // Environment
                Section("Environment") {
                    Picker("Environment", selection: $environmentLabel) {
                        Text("None").tag(nil as EnvironmentLabel?)
                        ForEach(EnvironmentLabel.allCases.filter { $0 != .custom }) { env in
                            HStack {
                                Circle().fill(env.color).frame(width: 8, height: 8)
                                Text(env.rawValue)
                            }
                            .tag(env as EnvironmentLabel?)
                        }
                        Text("Custom").tag(EnvironmentLabel.custom as EnvironmentLabel?)
                    }

                    if environmentLabel == .custom {
                        TextField("Custom environment", text: $customEnvironment)
                    }
                }

                // Options
                Section("Options") {
                    TextField("Connection Name (optional)", text: $connectionName,
                             prompt: Text("e.g. BLMS Prod, Auth Dev"))
                    Toggle("Trust Server Certificate", isOn: $trustCert)
                    Toggle("Encrypt", isOn: $encrypt)
                    Toggle("Save Connection", isOn: $saveConnection)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Status + buttons
            VStack(spacing: 8) {
                if !statusMessage.isEmpty {
                    HStack {
                        Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isError ? .red : .green)
                        Text(statusMessage)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Connect") {
                        Task { await connect() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnecting || (!manualMode && selectedDatabase == nil && authService.isSignedIn))
                }
                .padding()
            }
        }
        .frame(width: 520, height: 680)
    }

    private func connect() async {
        isConnecting = true
        statusMessage = "Connecting..."
        isError = false

        let serverName: String
        let dbName: String
        let connUsername: String?
        let connPassword: String?

        if manualMode {
            serverName = server
            dbName = database
            connUsername = username
            connPassword = password
        } else if let db = selectedDatabase {
            serverName = db.serverFqdn
            dbName = db.databaseName
            // For Entra ID, get a SQL access token and pass as password
            if let sqlToken = await authService.getSQLToken() {
                connUsername = authService.userEmail
                connPassword = sqlToken
            } else {
                statusMessage = "Failed to get SQL access token"
                isError = true
                isConnecting = false
                return
            }
        } else {
            statusMessage = "Select a database first"
            isError = true
            isConnecting = false
            return
        }

        let displayName = connectionName.isEmpty ? "\(dbName)  —  \(serverName)" : connectionName

        let info = ConnectionInfo(
            name: displayName,
            server: serverName,
            port: manualMode ? (Int(port) ?? 1433) : 1433,
            database: dbName,
            authType: manualMode ? .sqlAuthentication : .entraIdInteractive,
            username: connUsername,
            password: connPassword,
            trustServerCertificate: trustCert,
            encrypt: encrypt
        )

        do {
            let connId = try await appState.connectionManager.connect(info)
            appState.activeConnectionId = connId
            appState.currentDatabase = dbName
            appState.statusMessage = "Connected to \(serverName)"

            if saveConnection {
                let envLabel = environmentLabel == .custom ? customEnvironment : environmentLabel?.rawValue
                let saved = SavedConnection(
                    id: info.id, name: displayName, server: serverName,
                    port: info.port, database: dbName, authType: info.authType,
                    username: info.username, groupId: selectedGroup?.id,
                    environmentLabel: envLabel
                )
                appState.connectionStore.saveConnection(saved)
            }

            let serverNode = DatabaseObject(
                name: displayName,
                connectionId: connId,
                objectType: .server,
                isExpandable: true
            )
            appState.explorerNodes.append(serverNode)
            dismiss()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isError = true
        }
        isConnecting = false
    }
}
