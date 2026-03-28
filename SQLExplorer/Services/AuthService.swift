import Foundation
import MSAL

/// Entra ID authentication using MSAL.Swift + Azure subscription/database discovery
@MainActor
class AuthService: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String = ""
    @Published var errorMessage: String?

    // Azure discovery
    @Published var subscriptions: [AzureSubscription] = []
    @Published var isLoadingSubscriptions: Bool = false
    @Published var databases: [AzureDatabase] = []
    @Published var isLoadingDatabases: Bool = false
    @Published var selectedSubscription: AzureSubscription?

    private var application: MSALPublicClientApplication?
    private var account: MSALAccount?
    private var armAccessToken: String?

    private static let clientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46" // Azure CLI
    private static let authority = "https://login.microsoftonline.com/organizations"
    private static let armScopes = ["https://management.azure.com/.default"]
    private static let sqlScopes = ["https://database.windows.net/.default"]

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

    // MARK: - Auth

    /// Restore session from Keychain — runs on app launch
    func tryRestoreSession() async {
        guard let app = application else {
            print("[Auth] No MSAL app for restore")
            return
        }

        do {
            let accounts = try app.allAccounts()
            print("[Auth] Restore: found \(accounts.count) cached account(s)")
            guard let account = accounts.first else {
                print("[Auth] No cached accounts — user must sign in")
                return
            }

            self.account = account
            print("[Auth] Trying silent token for: \(account.username ?? "unknown")")

            let silentParams = MSALSilentTokenParameters(scopes: Self.armScopes, account: account)
            let result = try await app.acquireTokenSilent(with: silentParams)

            armAccessToken = result.accessToken
            userEmail = account.username ?? "Signed in"
            isSignedIn = true
            print("[Auth] Silent restore succeeded — isSignedIn = true")

            await discoverSubscriptions()
        } catch {
            print("[Auth] Silent restore failed: \(error)")
            isSignedIn = false
        }
    }

    /// Interactive sign-in via embedded WKWebView
    func signIn() async {
        guard let app = application else {
            errorMessage = "MSAL not initialized"
            return
        }

        do {
            let webviewParams = MSALWebviewParameters()
            webviewParams.webviewType = .wkWebView

            let params = MSALInteractiveTokenParameters(scopes: Self.armScopes, webviewParameters: webviewParams)
            params.promptType = .selectAccount

            print("[Auth] Starting interactive sign-in...")
            let result = try await app.acquireToken(with: params)
            print("[Auth] Sign-in succeeded: \(result.account.username ?? "unknown")")

            account = result.account
            armAccessToken = result.accessToken
            userEmail = result.account.username ?? "Signed in"
            isSignedIn = true
            errorMessage = nil

            print("[Auth] isSignedIn = \(isSignedIn), email = \(userEmail)")

            // Discover subscriptions after sign-in
            await discoverSubscriptions()
        } catch {
            print("[Auth] Sign-in failed: \(error)")
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isSignedIn = false
        }
    }

    func signOut() {
        guard let app = application, let account else { return }
        try? app.remove(account)
        self.account = nil
        armAccessToken = nil
        userEmail = ""
        isSignedIn = false
        subscriptions = []
        databases = []
        selectedSubscription = nil
    }

    /// Get SQL access token for database connectivity
    func getSQLToken() async -> String? {
        guard let app = application, let account else { return nil }
        do {
            let params = MSALSilentTokenParameters(scopes: Self.sqlScopes, account: account)
            let result = try await app.acquireTokenSilent(with: params)
            return result.accessToken
        } catch {
            return nil
        }
    }

    // MARK: - Azure Discovery

    /// Discover all subscriptions for the signed-in user
    func discoverSubscriptions() async {
        guard let token = armAccessToken else {
            print("[Auth] No ARM token for subscription discovery")
            return
        }

        print("[Auth] Discovering subscriptions...")
        isLoadingSubscriptions = true
        defer { isLoadingSubscriptions = false }

        do {
            var request = URLRequest(url: URL(string: "https://management.azure.com/subscriptions?api-version=2022-12-01")!)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let values = json?["value"] as? [[String: Any]] else { return }

            subscriptions = values.compactMap { sub in
                guard let id = sub["subscriptionId"] as? String,
                      let name = sub["displayName"] as? String else { return nil }
                return AzureSubscription(id: id, name: name)
            }.sorted { $0.name < $1.name }

            // Auto-select first subscription
            if let first = subscriptions.first {
                selectedSubscription = first
                await discoverDatabases(subscriptionId: first.id, subscriptionName: first.name)
            }
        } catch {
            errorMessage = "Failed to load subscriptions: \(error.localizedDescription)"
        }
    }

    /// Discover SQL databases in a subscription
    func discoverDatabases(subscriptionId: String, subscriptionName: String) async {
        guard let token = armAccessToken else { return }

        isLoadingDatabases = true
        databases = []
        defer { isLoadingDatabases = false }

        do {
            // List SQL servers
            var serversReq = URLRequest(url: URL(string: "https://management.azure.com/subscriptions/\(subscriptionId)/providers/Microsoft.Sql/servers?api-version=2021-11-01")!)
            serversReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (serversData, _) = try await URLSession.shared.data(for: serversReq)
            let serversJson = try JSONSerialization.jsonObject(with: serversData) as? [String: Any]
            guard let servers = serversJson?["value"] as? [[String: Any]] else { return }

            var allDbs: [AzureDatabase] = []

            for server in servers {
                guard let serverId = server["id"] as? String,
                      let props = server["properties"] as? [String: Any],
                      let fqdn = props["fullyQualifiedDomainName"] as? String else { continue }

                // Extract resource group from server ID
                let parts = serverId.split(separator: "/")
                guard let rgIdx = parts.firstIndex(where: { $0.lowercased() == "resourcegroups" }),
                      rgIdx + 1 < parts.count,
                      let srvIdx = parts.firstIndex(where: { $0.lowercased() == "servers" }),
                      srvIdx + 1 < parts.count else { continue }
                let rg = String(parts[rgIdx + 1])
                let srvName = String(parts[srvIdx + 1])

                // List databases on this server
                var dbsReq = URLRequest(url: URL(string: "https://management.azure.com/subscriptions/\(subscriptionId)/resourceGroups/\(rg)/providers/Microsoft.Sql/servers/\(srvName)/databases?api-version=2021-11-01")!)
                dbsReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (dbsData, _) = try await URLSession.shared.data(for: dbsReq)
                let dbsJson = try JSONSerialization.jsonObject(with: dbsData) as? [String: Any]
                guard let dbs = dbsJson?["value"] as? [[String: Any]] else { continue }

                for db in dbs {
                    guard let dbName = db["name"] as? String, dbName != "master" else { continue }
                    allDbs.append(AzureDatabase(
                        subscriptionId: subscriptionId,
                        subscriptionName: subscriptionName,
                        resourceGroup: rg,
                        serverFqdn: fqdn,
                        databaseName: dbName
                    ))
                }
            }

            databases = allDbs.sorted { $0.databaseName < $1.databaseName }
        } catch {
            errorMessage = "Failed to load databases: \(error.localizedDescription)"
        }
    }
}
