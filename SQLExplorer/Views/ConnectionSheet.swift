import SwiftUI

/// Unified "New Connection" sheet. Three tabs:
/// - **Azure SQL** – picks from the user's discovered Azure databases (requires sign-in)
/// - **SQL Server (Form)** – host/port/db/user/pass + Encrypt/TrustServerCertificate
/// - **From Connection String** – paste a SqlClient-style string, parse, edit
///
/// All three modes share a footer where the user can mark the connection as a
/// favorite and/or drop it into a group. Manual entries store passwords in the
/// Keychain so they reconnect on relaunch.
struct ConnectionSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case azure = "Azure SQL"
        case form = "Form"
        case string = "Connection String"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .azure: return "cloud"
            case .form: return "square.grid.2x2"
            case .string: return "doc.plaintext"
            }
        }
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    var initialMode: Mode = .azure

    @State private var mode: Mode = .azure

    // Azure selection
    @State private var selectedDatabase: AzureDatabase?

    // Manual form fields
    @State private var server = ""
    @State private var port = "1433"
    @State private var database = "master"
    @State private var username = ""
    @State private var password = ""
    @State private var trustCert = true
    @State private var encrypt = true
    @State private var useEntraForManual = false  // .manualEntra vs .manualSqlAuth

    // Connection string
    @State private var connectionString = ""
    @State private var stringParseError: String?

    // Common
    @State private var alias = ""
    @State private var saveToFavorites = false
    @State private var selectedGroupId: UUID?
    @State private var newGroupName = ""
    @State private var isCreatingGroup = false

    @State private var isConnecting = false
    @State private var statusMessage = ""
    @State private var isError = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            modePicker
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .azure:  azureForm
                    case .form:   manualForm
                    case .string: connectionStringForm
                    }

                    Divider().padding(.vertical, 4)

                    saveSection
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 540, height: 700)
        .onAppear {
            mode = initialMode
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder.split.1x2")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("New Connection")
                    .font(.headline)
                if authService.isSignedIn {
                    Text(authService.userEmail)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Not signed in to Microsoft — manual connections still work")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Label(m.rawValue, systemImage: m.icon).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Azure tab

    @ViewBuilder
    private var azureForm: some View {
        if !authService.isSignedIn {
            VStack(spacing: 10) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Sign in to discover Azure SQL databases")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await authService.signIn() }
                } label: {
                    Label("Sign in with Microsoft", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                labeledRow("Subscription") {
                    Picker("", selection: Binding(
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
                    .labelsHidden()
                }

                labeledRow("Database") {
                    if authService.isLoadingDatabases {
                        ProgressView().controlSize(.small)
                    } else if authService.databases.isEmpty {
                        Text("No databases in this subscription")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: $selectedDatabase) {
                            Text("Select a database").tag(nil as AzureDatabase?)
                            ForEach(authService.databases) { db in
                                Text("\(db.databaseName)  ·  \(db.serverFqdn.replacingOccurrences(of: ".database.windows.net", with: ""))")
                                    .tag(db as AzureDatabase?)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Manual form tab

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledRow("Server") {
                TextField("myserver.example.com or 10.0.0.5", text: $server)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 10) {
                labeledRow("Port", width: 80) {
                    TextField("1433", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                labeledRow("Database") {
                    TextField("master", text: $database)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Toggle("Use Microsoft Entra ID (current sign-in)", isOn: $useEntraForManual)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!authService.isSignedIn)
                .help(authService.isSignedIn
                      ? "Authenticate to this server using your current Entra ID session"
                      : "Sign in with Microsoft first to use this option")

            if !useEntraForManual {
                labeledRow("Username") {
                    TextField("sa", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                labeledRow("Password") {
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Toggle("Encrypt", isOn: $encrypt)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("Trust Server Certificate", isOn: $trustCert)
                .toggleStyle(.switch).controlSize(.small)
        }
    }

    // MARK: - Connection string tab

    private var connectionStringForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste a SqlClient-style connection string. Fields populate the form on parse.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $connectionString)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

            HStack {
                Button {
                    parseConnectionString()
                } label: {
                    Label("Parse", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                Spacer()
                if let err = stringParseError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Live preview of what was parsed (read-only summary)
            if !server.isEmpty || !database.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parsed values")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    summaryRow("Server", server)
                    summaryRow("Port", port)
                    summaryRow("Database", database)
                    if !username.isEmpty { summaryRow("Username", username) }
                    summaryRow("Encrypt", encrypt ? "yes" : "no")
                    summaryRow("Trust Cert", trustCert ? "yes" : "no")
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(5)
            }
        }
    }

    // MARK: - Save section

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledRow("Alias (optional)") {
                TextField(defaultAliasPlaceholder, text: $alias)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Add to Favorites", isOn: $saveToFavorites)
                .toggleStyle(.switch).controlSize(.small)

            HStack(spacing: 6) {
                Text("Group")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: $selectedGroupId) {
                    Text("None").tag(nil as UUID?)
                    ForEach(appState.userDataStore.groups) { g in
                        Text(g.name).tag(g.id as UUID?)
                    }
                }
                .labelsHidden()
                Button {
                    isCreatingGroup.toggle()
                    newGroupName = ""
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }

            if isCreatingGroup {
                HStack {
                    TextField("New group name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create") {
                        let name = newGroupName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        let g = appState.userDataStore.addGroup(name: name)
                        selectedGroupId = g.id
                        isCreatingGroup = false
                        newGroupName = ""
                    }
                    .controlSize(.small)
                    .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            if !statusMessage.isEmpty {
                HStack {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? .red : .green)
                    Text(statusMessage).font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView().controlSize(.small).padding(.horizontal, 6)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isConnecting || !canConnect)
            }
            .padding(14)
        }
    }

    // MARK: - Connect dispatch

    private var canConnect: Bool {
        switch mode {
        case .azure: return selectedDatabase != nil
        case .form, .string: return !server.trimmingCharacters(in: .whitespaces).isEmpty
                                  && !database.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var defaultAliasPlaceholder: String {
        switch mode {
        case .azure: return selectedDatabase?.databaseName ?? "e.g. BLMS Prod"
        case .form, .string: return database.isEmpty ? "e.g. Local SQL" : database
        }
    }

    private func parseConnectionString() {
        do {
            let info = try ConnectionStringParser.parse(connectionString)
            server = info.server
            port = String(info.port)
            database = info.database
            username = info.username ?? ""
            password = info.password ?? ""
            encrypt = info.encrypt
            trustCert = info.trustServerCertificate
            useEntraForManual = info.authType == .entraIdInteractive
            stringParseError = nil
        } catch {
            stringParseError = error.localizedDescription
        }
    }

    @MainActor
    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        statusMessage = "Connecting..."
        isError = false

        switch mode {
        case .azure:
            await connectAzure()
        case .form, .string:
            await connectManualOrString()
        }
    }

    private func connectAzure() async {
        guard let db = selectedDatabase else { return }
        // Reuse the existing Explorer connect path so the connection ends up as a
        // first-class node (rather than a synthetic foreign one).
        if let node = appState.explorerNodes
            .flatMap({ $0.children })
            .first(where: { $0.name == db.databaseName && $0.serverFqdn == db.serverFqdn }) {
            await appState.connectToDatabase(node)
        } else {
            // Fall through to foreign path (cross-subscription)
            await appState.connectToFavorite(FavoriteDatabase(
                databaseName: db.databaseName, serverFqdn: db.serverFqdn,
                subscriptionId: db.subscriptionId, subscriptionName: db.subscriptionName))
        }

        // Persist if requested. For Azure, subscription is known.
        let resolvedAlias = alias.trimmingCharacters(in: .whitespaces).isEmpty ? db.databaseName : alias
        let descriptor = ConnectionDescriptor(
            kind: .azureEntra,
            databaseName: db.databaseName, serverFqdn: db.serverFqdn,
            alias: resolvedAlias,
            subscriptionId: db.subscriptionId, subscriptionName: db.subscriptionName)
        if saveToFavorites {
            appState.userDataStore.toggleFavorite(descriptor: descriptor)
        }
        if let groupId = selectedGroupId {
            appState.userDataStore.addToGroup(groupId: groupId, descriptor: descriptor)
        }
        dismiss()
    }

    private func connectManualOrString() async {
        let portInt = Int(port.trimmingCharacters(in: .whitespaces)) ?? 1433
        let trimmedServer = server.trimmingCharacters(in: .whitespaces)
        let trimmedDb = database.trimmingCharacters(in: .whitespaces)
        let resolvedAlias = alias.trimmingCharacters(in: .whitespaces).isEmpty ? trimmedDb : alias

        let info: ConnectionInfo
        if useEntraForManual {
            // Entra ID against a user-specified server. Token is fetched inside
            // connectManually's token path so we don't need it here.
            info = ConnectionInfo(
                name: "\(trimmedDb) — \(trimmedServer)",
                server: trimmedServer, port: portInt, database: trimmedDb,
                authType: .entraIdInteractive,
                username: authService.userEmail,
                password: nil, // filled in by connectManually using a fresh token
                trustServerCertificate: trustCert, encrypt: encrypt)
        } else {
            info = ConnectionInfo(
                name: "\(trimmedDb) — \(trimmedServer)",
                server: trimmedServer, port: portInt, database: trimmedDb,
                authType: .sqlAuthentication,
                username: username,
                password: password,
                trustServerCertificate: trustCert, encrypt: encrypt)
        }

        // For Entra-on-manual we need a token now (connectManually doesn't fetch).
        var infoToConnect = info
        if useEntraForManual {
            guard let token = await authService.getSQLToken() else {
                statusMessage = "Failed to get SQL token"
                isError = true
                return
            }
            infoToConnect.password = token
        }

        let success = await appState.connectManually(
            info: infoToConnect,
            saveAsFavorite: saveToFavorites,
            groupId: selectedGroupId,
            alias: resolvedAlias
        )
        if success {
            dismiss()
        } else {
            statusMessage = appState.statusMessage
            isError = true
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func labeledRow<Content: View>(_ label: String, width: CGFloat = 110, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: width, alignment: .leading)
            content()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
