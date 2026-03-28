import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var server = ""
    @State private var port = "1433"
    @State private var database = "master"
    @State private var authType: ConnectionAuthType = .entraIdInteractive
    @State private var username = ""
    @State private var password = ""
    @State private var connectionName = ""
    @State private var selectedGroup: ConnectionGroup?
    @State private var environmentLabel: EnvironmentLabel?
    @State private var customEnvironment = ""
    @State private var trustCert = true
    @State private var encrypt = true
    @State private var saveConnection = true

    @State private var isConnecting = false
    @State private var isTesting = false
    @State private var statusMessage = ""
    @State private var isError = false

    // Group editing
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cylinder.split.1x2")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Connect to Server")
                        .font(.headline)
                    Text("Azure SQL  ·  Local  ·  Docker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                // Auth section
                Section("Authentication") {
                    Picker("Method", selection: $authType) {
                        ForEach(ConnectionAuthType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if authType == .entraIdInteractive {
                        EntraSignInSection()
                    }
                }

                // Server (SQL Auth only)
                if authType == .sqlAuthentication {
                    Section("Server") {
                        TextField("Server", text: $server, prompt: Text("myserver.database.windows.net"))
                        TextField("Port", text: $port)
                        TextField("Database", text: $database, prompt: Text("master"))
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                    }
                }

                // Group + Environment
                Section("Organization") {
                    HStack {
                        Picker("Group", selection: $selectedGroup) {
                            Text("No group").tag(nil as ConnectionGroup?)
                            ForEach(appState.connectionStore.groups) { group in
                                Text(group.name).tag(group as ConnectionGroup?)
                            }
                        }

                        Button(action: { isCreatingGroup = true }) {
                            Image(systemName: "plus")
                        }
                    }

                    if isCreatingGroup {
                        HStack {
                            TextField("Group name", text: $newGroupName)
                            Button("Create") {
                                let group = ConnectionGroup(name: newGroupName)
                                appState.connectionStore.saveGroup(group)
                                selectedGroup = group
                                isCreatingGroup = false
                                newGroupName = ""
                            }
                            .disabled(newGroupName.isEmpty)
                            Button("Cancel") { isCreatingGroup = false }
                        }
                    }

                    Picker("Environment", selection: $environmentLabel) {
                        Text("None").tag(nil as EnvironmentLabel?)
                        ForEach(EnvironmentLabel.allCases.filter { $0 != .custom }) { env in
                            HStack {
                                Circle()
                                    .fill(env.color)
                                    .frame(width: 8, height: 8)
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
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting)

                    Spacer()

                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)

                    Button("Connect") {
                        Task { await connect() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnecting)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 650)
    }

    private func buildConnectionInfo() -> ConnectionInfo {
        ConnectionInfo(
            name: connectionName.isEmpty ? "\(database) (\(server))" : connectionName,
            server: server,
            port: Int(port) ?? 1433,
            database: database,
            authType: authType,
            username: authType == .sqlAuthentication ? username : nil,
            password: authType == .sqlAuthentication ? password : nil,
            trustServerCertificate: trustCert,
            encrypt: encrypt
        )
    }

    private func testConnection() async {
        isTesting = true
        statusMessage = "Testing..."
        isError = false

        let info = buildConnectionInfo()
        let success = await appState.connectionManager.testConnection(info)
        statusMessage = success ? "Connection successful!" : "Connection failed"
        isError = !success
        isTesting = false
    }

    private func connect() async {
        isConnecting = true
        statusMessage = "Connecting..."
        isError = false

        let info = buildConnectionInfo()
        do {
            let connId = try await appState.connectionManager.connect(info)
            appState.activeConnectionId = connId
            appState.currentDatabase = info.database
            appState.statusMessage = "Connected to \(info.server)"

            // Save if requested
            if saveConnection {
                let envLabel = environmentLabel == .custom ? customEnvironment : environmentLabel?.rawValue
                let saved = SavedConnection(
                    id: info.id,
                    name: info.name,
                    server: info.server,
                    port: info.port,
                    database: info.database,
                    authType: info.authType,
                    username: info.username,
                    groupId: selectedGroup?.id,
                    environmentLabel: envLabel
                )
                appState.connectionStore.saveConnection(saved)
            }

            // Build explorer tree
            let serverNode = DatabaseObject(
                name: "\(info.database)  —  \(info.server)",
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

struct EntraSignInSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.authService.isSignedIn {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(appState.authService.userEmail)
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
            }
        } else {
            Button("Sign in with Microsoft") {
                Task { await appState.authService.signIn() }
            }
        }
    }
}
