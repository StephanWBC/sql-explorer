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

    /// Cross-subscription FQDN → subscription map. Populated in the background after
    /// sign-in by `discoverAllSubscriptionDatabases()`. Lets us resolve which Azure
    /// subscription a given server belongs to, regardless of which is currently
    /// selected in the picker. This is what powers the cross-subscription pill in
    /// Groups/Favorites — without it, members get tagged with whichever subscription
    /// happened to be active at add-time.
    @Published var serverToSubscription: [String: AzureSubscription] = [:]

    /// Every Azure SQL database the user can see across every subscription. Populated
    /// alongside `serverToSubscription` so cross-sub features (e.g. Performance on a
    /// member from a different subscription) can resolve the AzureDatabase + its
    /// resourceGroup without forcing a subscription switch.
    @Published var crossSubDatabases: [AzureDatabase] = []

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
            // Use explicit Keychain group to avoid stale entries after reinstall/re-sign
            config.cacheConfig.keychainSharingGroup = "com.sqlexplorer.app"
            application = try MSALPublicClientApplication(configuration: config)
        } catch {
            errorMessage = "MSAL setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session Restore

    func tryRestoreSession() async {
        AppLogger.auth.info("Attempting session restore")
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
            AppLogger.auth.warning("Session restore failed: \(error.localizedDescription)")
            // Clear stale Keychain cache on any MSAL error to prevent -50000 on next sign-in
            clearMSALCache()
            isSignedIn = false
        }
    }

    // MARK: - Sign In / Out

    func signIn() async {
        AppLogger.auth.info("Interactive sign-in started")
        guard let app = application else { return }
        errorMessage = nil

        do {
            let result = try await performInteractiveSignIn(app: app)
            account = result.account
            armAccessToken = result.accessToken
            userEmail = result.account.username ?? "Signed in"
            isSignedIn = true
            errorMessage = nil
            await discoverSubscriptions()
        } catch let error as NSError where error.domain == MSALErrorDomain && error.code == -50000 {
            // Keychain error — clear stale cache and retry once
            AppLogger.auth.warning("Keychain error (-50000), clearing cache and retrying")
            clearMSALCache()
            do {
                let result = try await performInteractiveSignIn(app: app)
                account = result.account
                armAccessToken = result.accessToken
                userEmail = result.account.username ?? "Signed in"
                isSignedIn = true
                errorMessage = nil
                await discoverSubscriptions()
            } catch {
                AppLogger.auth.error("Sign-in retry failed: \(error.localizedDescription)")
                errorMessage = "Sign-in failed. Please try again."
                isSignedIn = false
            }
        } catch {
            AppLogger.auth.error("Sign-in failed: \(error.localizedDescription)")
            errorMessage = "Sign-in failed. Please try again."
            isSignedIn = false
        }
    }

    private func performInteractiveSignIn(app: MSALPublicClientApplication) async throws -> MSALResult {
        let webviewParams = MSALWebviewParameters()
        webviewParams.webviewType = .wkWebView
        let params = MSALInteractiveTokenParameters(scopes: Self.armScopes, webviewParameters: webviewParams)
        params.promptType = .selectAccount
        return try await app.acquireToken(with: params)
    }

    /// Clears all MSAL cached accounts to recover from Keychain errors (e.g. after reinstall)
    private func clearMSALCache() {
        guard let app = application else { return }
        do {
            let accounts = try app.allAccounts()
            for acct in accounts {
                try app.remove(acct)
            }
            AppLogger.auth.info("Cleared \(accounts.count) stale MSAL account(s)")
        } catch {
            AppLogger.auth.warning("Failed to clear MSAL cache: \(error.localizedDescription)")
        }
        account = nil
        armAccessToken = nil
    }

    func signOut() {
        clearMSALCache()
        userEmail = ""
        isSignedIn = false
        subscriptions = []
        databases = []
        selectedSubscription = nil
        serverToSubscription = [:]
        crossSubDatabases = []
        errorMessage = nil
    }

    // MARK: - Cross-subscription server lookup

    /// Returns the subscription this server lives in, or `nil` if the cross-subscription
    /// map hasn't loaded yet (or the server isn't in any of the user's subscriptions).
    /// Use this at add-to-Group/Favorites time so badges work even when the user is
    /// looking at a different subscription's tree.
    func subscription(forServerFqdn fqdn: String) -> AzureSubscription? {
        serverToSubscription[fqdn]
    }

    // MARK: - SQL Token

    func getSQLToken() async -> String? {
        guard let app = application, let account else { return nil }

        // Try silent token first (uses cached refresh token — no user interaction)
        do {
            let params = MSALSilentTokenParameters(scopes: Self.sqlScopes, account: account)
            return try await app.acquireTokenSilent(with: params).accessToken
        } catch {
            AppLogger.auth.warning("Silent SQL token failed, falling back to interactive: \(error.localizedDescription)")
        }

        // Fall back to interactive auth
        do {
            let webviewParams = MSALWebviewParameters()
            webviewParams.webviewType = .wkWebView
            let params = MSALInteractiveTokenParameters(scopes: Self.sqlScopes, webviewParameters: webviewParams)
            return try await app.acquireToken(with: params).accessToken
        } catch {
            errorMessage = "SQL token failed. Please sign out and sign in again."
            return nil
        }
    }

    // MARK: - ARM Token

    /// Get a fresh ARM token. Tries silent acquisition first, falls back to interactive auth.
    /// Updates the cached `armAccessToken` on success.
    func getARMToken() async -> String? {
        guard let app = application, let account else { return nil }

        do {
            let params = MSALSilentTokenParameters(scopes: Self.armScopes, account: account)
            let result = try await app.acquireTokenSilent(with: params)
            armAccessToken = result.accessToken
            return result.accessToken
        } catch {
            AppLogger.auth.warning("Silent ARM token failed, falling back to interactive: \(error.localizedDescription)")
        }

        do {
            let webviewParams = MSALWebviewParameters()
            webviewParams.webviewType = .wkWebView
            let params = MSALInteractiveTokenParameters(scopes: Self.armScopes, webviewParameters: webviewParams)
            let result = try await app.acquireToken(with: params)
            armAccessToken = result.accessToken
            return result.accessToken
        } catch {
            errorMessage = "ARM token failed. Please sign out and sign in again."
            return nil
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

            // Fan out a non-blocking discovery across every subscription so we can
            // resolve which sub a given server lives in — without forcing the user
            // to switch the picker. Powers cross-subscription pills + the badge fix
            // for already-saved Group/Favorite members.
            Task { [weak self] in await self?.discoverAllSubscriptionDatabases() }
        } catch {
            errorMessage = "Subscriptions: \(error.localizedDescription)"
        }
    }

    /// Walks every subscription the user has access to, lists its SQL servers AND
    /// each server's databases, and builds two lookups:
    /// - `serverFqdn → AzureSubscription` (powers cross-sub pills)
    /// - `crossSubDatabases: [AzureDatabase]` (powers cross-sub Performance + future
    ///   features that need full ARM context like resourceGroup)
    /// Runs once after sign-in. Failures on individual subscriptions are non-fatal.
    func discoverAllSubscriptionDatabases() async {
        guard let token = armAccessToken else { return }
        var map: [String: AzureSubscription] = [:]
        var allDbs: [AzureDatabase] = []

        for sub in subscriptions {
            do {
                var serversReq = URLRequest(url: URL(string: "https://management.azure.com/subscriptions/\(sub.id)/providers/Microsoft.Sql/servers?api-version=2021-11-01")!)
                serversReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                serversReq.timeoutInterval = 30
                let (data, _) = try await URLSession.shared.data(for: serversReq)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let servers = json?["value"] as? [[String: Any]] else { continue }

                for server in servers {
                    guard let serverId = server["id"] as? String,
                          let props = server["properties"] as? [String: Any],
                          let fqdn = props["fullyQualifiedDomainName"] as? String else { continue }
                    map[fqdn] = sub

                    let parts = serverId.split(separator: "/")
                    guard let rgIdx = parts.firstIndex(where: { $0.lowercased() == "resourcegroups" }),
                          rgIdx + 1 < parts.count,
                          let srvIdx = parts.firstIndex(where: { $0.lowercased() == "servers" }),
                          srvIdx + 1 < parts.count else { continue }
                    let rg = String(parts[rgIdx + 1])
                    let srvName = String(parts[srvIdx + 1])

                    do {
                        var dbsReq = URLRequest(url: URL(string: "https://management.azure.com/subscriptions/\(sub.id)/resourceGroups/\(rg)/providers/Microsoft.Sql/servers/\(srvName)/databases?api-version=2021-11-01")!)
                        dbsReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        dbsReq.timeoutInterval = 30
                        let (dbsData, _) = try await URLSession.shared.data(for: dbsReq)
                        let dbsJson = try JSONSerialization.jsonObject(with: dbsData) as? [String: Any]
                        guard let dbs = dbsJson?["value"] as? [[String: Any]] else { continue }
                        for db in dbs {
                            guard let dbName = db["name"] as? String, dbName != "master" else { continue }
                            allDbs.append(AzureDatabase(
                                subscriptionId: sub.id, subscriptionName: sub.name,
                                resourceGroup: rg, serverFqdn: fqdn, databaseName: dbName))
                        }
                    } catch {
                        AppLogger.auth.warning("Cross-sub db enum failed for \(srvName) in \(sub.name): \(error.localizedDescription)")
                    }
                }
            } catch {
                AppLogger.auth.warning("Cross-sub server enum failed for \(sub.name): \(error.localizedDescription)")
            }
        }

        serverToSubscription = map
        crossSubDatabases = allDbs
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
