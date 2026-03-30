import Foundation
import MSAL

/// Clean Entra ID authentication — no hacks, no manual Keychain, just MSAL
@MainActor
class AuthService: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String = ""
    @Published var errorMessage: String?

    @Published var subscriptions: [AzureSubscription] = []
    @Published var isLoadingSubscriptions: Bool = false
    @Published var databases: [AzureDatabase] = []
    @Published var isLoadingDatabases: Bool = false
    @Published var selectedSubscription: AzureSubscription?

    private var application: MSALPublicClientApplication?
    private var account: MSALAccount?
    private var armAccessToken: String?

    private static let clientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
    private static let authority = "https://login.microsoftonline.com/organizations"
    private static let armScopes = ["https://management.azure.com/.default"]
    private static let sqlScopes = ["https://database.windows.net/.default"]

    private static let storeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sqlexplorer")
    private static let defaultSubFile = storeDir.appendingPathComponent("default-subscription.txt")

    init() {
        setupMSAL()
        Task { await tryRestoreSession() }
    }

    private func setupMSAL() {
        do {
            let config = MSALPublicClientApplicationConfig(clientId: Self.clientId)
            config.authority = try MSALAuthority(url: URL(string: Self.authority)!)
            config.redirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"
            application = try MSALPublicClientApplication(configuration: config)
        } catch {
            errorMessage = "MSAL setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session Restore

    func tryRestoreSession() async {
        guard let app = application else { return }

        do {
            let accounts = try app.allAccounts()
            guard let acct = accounts.first else { return }

            self.account = acct
            let params = MSALSilentTokenParameters(scopes: Self.armScopes, account: acct)
            let result = try await app.acquireTokenSilent(with: params)

            armAccessToken = result.accessToken
            userEmail = acct.username ?? "Signed in"
            isSignedIn = true
            await discoverSubscriptions()
        } catch {
            // Can't restore silently — that's fine, user will sign in
            isSignedIn = false
        }
    }

    // MARK: - Sign In / Out

    func signIn() async {
        guard let app = application else { return }

        do {
            let webviewParams = MSALWebviewParameters()
            webviewParams.webviewType = .wkWebView
            let params = MSALInteractiveTokenParameters(scopes: Self.armScopes, webviewParameters: webviewParams)
            params.promptType = .selectAccount

            let result = try await app.acquireToken(with: params)

            account = result.account
            armAccessToken = result.accessToken
            userEmail = result.account.username ?? "Signed in"
            isSignedIn = true
            errorMessage = nil

            await discoverSubscriptions()
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isSignedIn = false
        }
    }

    func signOut() {
        if let app = application, let account {
            try? app.remove(account)
        }
        account = nil
        armAccessToken = nil
        userEmail = ""
        isSignedIn = false
        subscriptions = []
        databases = []
        selectedSubscription = nil
        errorMessage = nil
    }

    // MARK: - SQL Token

    func getSQLToken() async -> String? {
        guard let app = application, let account else { return nil }

        do {
            let params = MSALSilentTokenParameters(scopes: Self.sqlScopes, account: account)
            return try await app.acquireTokenSilent(with: params).accessToken
        } catch {
            do {
                let webviewParams = MSALWebviewParameters()
                webviewParams.webviewType = .wkWebView
                let params = MSALInteractiveTokenParameters(scopes: Self.sqlScopes, webviewParameters: webviewParams)
                return try await app.acquireToken(with: params).accessToken
            } catch {
                errorMessage = "SQL token failed: \(error.localizedDescription)"
                return nil
            }
        }
    }

    // MARK: - Default Subscription

    func saveDefaultSubscriptionId(_ id: String) {
        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        try? id.write(to: Self.defaultSubFile, atomically: true, encoding: .utf8)
    }

    private func loadDefaultSubscriptionId() -> String? {
        try? String(contentsOf: Self.defaultSubFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Azure Discovery

    func discoverSubscriptions() async {
        guard let token = armAccessToken else { return }
        isLoadingSubscriptions = true
        defer { isLoadingSubscriptions = false }

        do {
            var req = URLRequest(url: URL(string: "https://management.azure.com/subscriptions?api-version=2022-12-01")!)
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 30
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let values = json?["value"] as? [[String: Any]] else { return }

            subscriptions = values.compactMap { sub in
                guard let id = sub["subscriptionId"] as? String,
                      let name = sub["displayName"] as? String else { return nil }
                return AzureSubscription(id: id, name: name)
            }.sorted { $0.name < $1.name }

            let defaultId = loadDefaultSubscriptionId()
            let selected = subscriptions.first(where: { $0.id == defaultId }) ?? subscriptions.first
            if let selected {
                selectedSubscription = selected
                await discoverDatabases(subscriptionId: selected.id, subscriptionName: selected.name)
            }
        } catch {
            errorMessage = "Subscriptions: \(error.localizedDescription)"
        }
    }

    func discoverDatabases(subscriptionId: String, subscriptionName: String) async {
        guard let token = armAccessToken else { return }
        isLoadingDatabases = true
        databases = []
        defer { isLoadingDatabases = false }

        do {
            var serversReq = URLRequest(url: URL(string: "https://management.azure.com/subscriptions/\(subscriptionId)/providers/Microsoft.Sql/servers?api-version=2021-11-01")!)
            serversReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            serversReq.timeoutInterval = 30
            let (serversData, _) = try await URLSession.shared.data(for: serversReq)
            let serversJson = try JSONSerialization.jsonObject(with: serversData) as? [String: Any]
            guard let servers = serversJson?["value"] as? [[String: Any]] else { return }

            var allDbs: [AzureDatabase] = []
            for server in servers {
                guard let serverId = server["id"] as? String,
                      let props = server["properties"] as? [String: Any],
                      let fqdn = props["fullyQualifiedDomainName"] as? String else { continue }
                let parts = serverId.split(separator: "/")
                guard let rgIdx = parts.firstIndex(where: { $0.lowercased() == "resourcegroups" }),
                      rgIdx + 1 < parts.count,
                      let srvIdx = parts.firstIndex(where: { $0.lowercased() == "servers" }),
                      srvIdx + 1 < parts.count else { continue }
                let rg = String(parts[rgIdx + 1])
                let srvName = String(parts[srvIdx + 1])

                var dbsReq = URLRequest(url: URL(string: "https://management.azure.com/subscriptions/\(subscriptionId)/resourceGroups/\(rg)/providers/Microsoft.Sql/servers/\(srvName)/databases?api-version=2021-11-01")!)
                dbsReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                dbsReq.timeoutInterval = 30
                let (dbsData, _) = try await URLSession.shared.data(for: dbsReq)
                let dbsJson = try JSONSerialization.jsonObject(with: dbsData) as? [String: Any]
                guard let dbs = dbsJson?["value"] as? [[String: Any]] else { continue }

                for db in dbs {
                    guard let dbName = db["name"] as? String, dbName != "master" else { continue }
                    allDbs.append(AzureDatabase(subscriptionId: subscriptionId, subscriptionName: subscriptionName,
                                                resourceGroup: rg, serverFqdn: fqdn, databaseName: dbName))
                }
            }
            databases = allDbs.sorted { $0.databaseName < $1.databaseName }
        } catch {
            errorMessage = "Databases: \(error.localizedDescription)"
        }
    }
}
