import Foundation
import MSAL

/// Entra ID authentication using MSAL.Swift + Azure subscription/database discovery
///
/// Token persistence strategy:
/// 1. MSAL's built-in Keychain cache (if entitlements allow)
/// 2. Manual Keychain backup of account identifier + home account ID
/// 3. On restore: find account by ID in MSAL cache, then silent token refresh
///
/// The user logs in ONCE. Until they explicitly sign out, the token persists
/// across app restarts, updates, reinstalls (Keychain is tied to bundle ID).
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

    private static let clientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
    private static let authority = "https://login.microsoftonline.com/organizations"
    private static let armScopes = ["https://management.azure.com/.default"]
    private static let sqlScopes = ["https://database.windows.net/.default"]

    // Persistent storage keys
    private static let savedAccountFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sqlexplorer/auth-account.json")
    private static let keychainAccountKey = "com.sqlexplorer.msal-account-id"
    private static let keychainEmailKey = "com.sqlexplorer.user-email"

    init() {
        setupMSAL()
        Task { await tryRestoreSession() }
    }

    // MARK: - MSAL Setup

    private func setupMSAL() {
        do {
            let config = MSALPublicClientApplicationConfig(clientId: Self.clientId)
            config.authority = try MSALAuthority(url: URL(string: Self.authority)!)
            config.redirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"

            application = try MSALPublicClientApplication(configuration: config)
            print("[Auth] MSAL initialized successfully")
        } catch {
            print("[Auth] MSAL setup failed: \(error)")
            errorMessage = "MSAL setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session Restore (THE CRITICAL PATH)

    /// Restore session — this is what makes "log in once, forever" work
    func tryRestoreSession() async {
        guard let app = application else {
            print("[Auth] No MSAL app — can't restore")
            return
        }

        // Step 1: Try to find cached accounts in MSAL's own cache
        do {
            let accounts = try app.allAccounts()
            print("[Auth] MSAL cache has \(accounts.count) account(s)")

            if let account = accounts.first {
                // Great — MSAL has the account cached
                return await restoreWithAccount(account, app: app)
            }
        } catch {
            print("[Auth] Error reading MSAL accounts: \(error)")
        }

        // Step 2: MSAL cache empty — try our manual backup
        if let savedAccountId = KeychainHelper.load(key: Self.keychainAccountKey),
           let savedEmail = KeychainHelper.load(key: Self.keychainEmailKey) {
            print("[Auth] Found saved account in Keychain: \(savedEmail)")

            // Try to find account by identifier
            do {
                let account = try app.account(forIdentifier: savedAccountId)
                return await restoreWithAccount(account, app: app)
            } catch {
                print("[Auth] Could not find account by ID: \(error)")
            }

            // Last resort: show the email but mark as needing re-auth
            print("[Auth] Account found in Keychain but MSAL can't locate it")
            userEmail = savedEmail
        }

        // Step 3: Check file-based backup
        if let data = try? Data(contentsOf: Self.savedAccountFile),
           let saved = try? JSONDecoder().decode(SavedAuthAccount.self, from: data) {
            print("[Auth] Found auth file backup: \(saved.email)")
            userEmail = saved.email

            do {
                let account = try app.account(forIdentifier: saved.accountId)
                return await restoreWithAccount(account, app: app)
            } catch {
                print("[Auth] File backup account not in MSAL: \(error)")
            }
        }

        print("[Auth] No cached session found — user must sign in")
        isSignedIn = false
    }

    /// Restore using a found MSAL account — silent token refresh
    private func restoreWithAccount(_ account: MSALAccount, app: MSALPublicClientApplication) async {
        self.account = account
        let email = account.username ?? "Signed in"
        userEmail = email
        print("[Auth] Restoring session for: \(email)")

        do {
            let silentParams = MSALSilentTokenParameters(scopes: Self.armScopes, account: account)
            let result = try await app.acquireTokenSilent(with: silentParams)

            armAccessToken = result.accessToken
            isSignedIn = true
            print("[Auth] ✅ Silent restore succeeded — isSignedIn = true")

            // Save backup
            persistAccountInfo(account: account, email: email)

            // Discover subscriptions
            await discoverSubscriptions()
        } catch {
            print("[Auth] Silent token refresh failed: \(error)")
            // Token expired but account exists — try interactive silently
            // (MSAL may be able to use the refresh token)
            errorMessage = "Session expired. Please sign in again."
            isSignedIn = false
        }
    }

    // MARK: - Interactive Sign-In

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

            account = result.account
            armAccessToken = result.accessToken
            let email = result.account.username ?? "Signed in"
            userEmail = email
            isSignedIn = true
            errorMessage = nil

            print("[Auth] ✅ Interactive sign-in succeeded: \(email)")

            // Persist account info in MULTIPLE places for reliability
            persistAccountInfo(account: result.account, email: email)

            await discoverSubscriptions()
        } catch {
            print("[Auth] ❌ Sign-in failed: \(error)")
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isSignedIn = false
        }
    }

    // MARK: - Persistence (belt AND suspenders)

    /// Save account info to Keychain + file so we can find it on next launch
    private func persistAccountInfo(account: MSALAccount, email: String) {
        let accountId = account.identifier ?? ""

        // Keychain backup
        KeychainHelper.save(key: Self.keychainAccountKey, value: accountId)
        KeychainHelper.save(key: Self.keychainEmailKey, value: email)

        // File backup
        let saved = SavedAuthAccount(accountId: accountId, email: email, savedAt: Date())
        if let data = try? JSONEncoder().encode(saved) {
            let dir = Self.savedAccountFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: Self.savedAccountFile, options: .atomic)
        }

        print("[Auth] Persisted account: \(email) (id: \(accountId.prefix(8))...)")
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

        // Clear all persistence
        KeychainHelper.delete(key: Self.keychainAccountKey)
        KeychainHelper.delete(key: Self.keychainEmailKey)
        try? FileManager.default.removeItem(at: Self.savedAccountFile)

        print("[Auth] Signed out — all cached data cleared")
    }

    // MARK: - SQL Token

    func getSQLToken() async -> String? {
        guard let app = application, let account else { return nil }

        // Try silent
        do {
            let params = MSALSilentTokenParameters(scopes: Self.sqlScopes, account: account)
            let result = try await app.acquireTokenSilent(with: params)
            return result.accessToken
        } catch {
            print("[Auth] SQL silent token failed: \(error)")
        }

        // Interactive fallback
        do {
            let webviewParams = MSALWebviewParameters()
            webviewParams.webviewType = .wkWebView
            let params = MSALInteractiveTokenParameters(scopes: Self.sqlScopes, webviewParameters: webviewParams)
            let result = try await app.acquireToken(with: params)
            return result.accessToken
        } catch {
            print("[Auth] SQL interactive token failed: \(error)")
            errorMessage = "SQL token failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Azure Discovery

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
            request.timeoutInterval = 30

            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let values = json?["value"] as? [[String: Any]] else { return }

            subscriptions = values.compactMap { sub in
                guard let id = sub["subscriptionId"] as? String,
                      let name = sub["displayName"] as? String else { return nil }
                return AzureSubscription(id: id, name: name)
            }.sorted { $0.name < $1.name }

            print("[Auth] Found \(subscriptions.count) subscription(s)")

            if let first = subscriptions.first {
                selectedSubscription = first
                await discoverDatabases(subscriptionId: first.id, subscriptionName: first.name)
            }
        } catch {
            print("[Auth] Subscription discovery failed: \(error)")
            errorMessage = "Failed to load subscriptions: \(error.localizedDescription)"
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
            print("[Auth] Found \(databases.count) database(s)")
        } catch {
            print("[Auth] Database discovery failed: \(error)")
            errorMessage = "Failed to load databases: \(error.localizedDescription)"
        }
    }
}

// MARK: - Persistence model

private struct SavedAuthAccount: Codable {
    let accountId: String
    let email: String
    let savedAt: Date
}
