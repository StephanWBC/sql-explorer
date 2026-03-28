import Foundation
import MSAL

/// Entra ID authentication — MSAL for interactive login, manual Keychain for persistence
///
/// Strategy: MSAL's Keychain persistence is unreliable with ad-hoc signed SPM apps.
/// Instead, we serialize MSAL's entire token cache data to our own Keychain entry.
/// On restore, we deserialize it back. This gives us full control.
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

    private static let storeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sqlexplorer")
    private static let cacheFile = storeDir.appendingPathComponent("msal-cache.json")
    private static let emailFile = storeDir.appendingPathComponent("auth-email.txt")

    // MSAL Keychain identifiers (where MSAL reads/writes its cache)
    private static let msalKeychainService = "SqlExplorer"
    private static let msalKeychainAccount = "MSALTokenCache"

    init() {
        restoreMSALCacheFromFile()  // BEFORE MSAL init — inject cache into Keychain
        setupMSAL()
        Task { await tryRestoreSession() }
    }

    /// Restore MSAL's Keychain cache from our file backup
    /// This is needed because each DMG build has a different ad-hoc signature,
    /// so Keychain items from the previous build are inaccessible.
    /// We save the cache blob to a file and restore it before MSAL initializes.
    private func restoreMSALCacheFromFile() {
        guard let data = try? Data(contentsOf: Self.cacheFile) else { return }
        print("[Auth] Restoring MSAL cache from file (\(data.count) bytes)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.msalKeychainService,
            kSecAttrAccount as String: Self.msalKeychainAccount,
        ]

        // Try update first (if entry exists from same or different app version)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            print("[Auth] Keychain update succeeded")
            return
        }

        // If update failed (item not found), delete everything matching and re-add
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        print("[Auth] Keychain add status: \(addStatus) (0=success, -25299=duplicate)")

        // If still duplicate, try updating without matching account
        if addStatus == -25299 {
            let broadQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.msalKeychainService,
            ]
            let broadUpdate = SecItemUpdate(
                broadQuery as CFDictionary,
                [kSecValueData as String: data, kSecAttrAccount as String: Self.msalKeychainAccount] as CFDictionary
            )
            print("[Auth] Broad update status: \(broadUpdate)")
        }
    }

    /// Save MSAL's Keychain cache to our file backup
    private func saveMSALCacheToFile() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.msalKeychainService,
            kSecAttrAccount as String: Self.msalKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            print("[Auth] Could not read MSAL cache from Keychain: \(status)")
            return
        }

        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        try? data.write(to: Self.cacheFile, options: .atomic)
        print("[Auth] Saved MSAL cache to file (\(data.count) bytes)")
    }

    private func saveEmail(_ email: String) {
        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        try? email.write(to: Self.emailFile, atomically: true, encoding: .utf8)
    }

    private func loadSavedEmail() -> String? {
        try? String(contentsOf: Self.emailFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearAllPersistence() {
        try? FileManager.default.removeItem(at: Self.cacheFile)
        try? FileManager.default.removeItem(at: Self.emailFile)
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

    // MARK: - Restore (THE critical path)

    func tryRestoreSession() async {
        guard let app = application else { return }

        // Check if we have a saved email (means user logged in before)
        guard let savedEmail = loadSavedEmail() ?? KeychainHelper.load(key: "com.sqlexplorer.user-email") else {
            print("[Auth] No saved email — first launch, user must sign in")
            return
        }

        userEmail = savedEmail
        print("[Auth] Found saved session for: \(savedEmail)")

        // Try to find MSAL account
        do {
            let accounts = try app.allAccounts()
            print("[Auth] MSAL has \(accounts.count) account(s)")

            if let acct = accounts.first {
                self.account = acct
                // Try silent token refresh
                let params = MSALSilentTokenParameters(scopes: Self.armScopes, account: acct)
                let result = try await app.acquireTokenSilent(with: params)
                armAccessToken = result.accessToken
                isSignedIn = true
                saveMSALCacheToFile()  // Keep file backup fresh
                print("[Auth] ✅ Restored from MSAL cache")
                await discoverSubscriptions()
                return
            }
        } catch {
            print("[Auth] MSAL restore failed: \(error)")
        }

        // MSAL cache empty — try finding by saved account ID
        if let savedId = KeychainHelper.load(key: "com.sqlexplorer.account-id") {
            do {
                let acct = try app.account(forIdentifier: savedId)
                self.account = acct
                let params = MSALSilentTokenParameters(scopes: Self.armScopes, account: acct)
                let result = try await app.acquireTokenSilent(with: params)
                armAccessToken = result.accessToken
                isSignedIn = true
                saveMSALCacheToFile()
                print("[Auth] ✅ Restored from saved account ID")
                await discoverSubscriptions()
                return
            } catch {
                print("[Auth] Account ID restore failed: \(error)")
            }
        }

        // All restore paths failed — but don't clear the email
        // Show the email but indicate re-auth needed
        print("[Auth] Session expired — user needs to re-authenticate")
        errorMessage = "Session expired. Please sign in again."
        isSignedIn = false
    }

    // MARK: - Sign In

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

            // PERSIST: save everything so next launch restores instantly
            let accountId = result.account.identifier ?? ""
            KeychainHelper.save(key: "com.sqlexplorer.user-email", value: userEmail)
            KeychainHelper.save(key: "com.sqlexplorer.account-id", value: accountId)
            saveEmail(userEmail)
            saveMSALCacheToFile()  // THE CRITICAL CALL — saves MSAL's token cache blob to file
            print("[Auth] ✅ Signed in and persisted: \(userEmail)")

            // Also try to pre-consent SQL scope so connect doesn't prompt later
            do {
                let sqlParams = MSALSilentTokenParameters(scopes: Self.sqlScopes, account: result.account)
                _ = try await app.acquireTokenSilent(with: sqlParams)
                saveMSALCacheToFile()  // Update file after SQL consent
                print("[Auth] SQL scope pre-consented silently")
            } catch {
                print("[Auth] SQL scope not yet consented (will prompt on connect)")
            }

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

        KeychainHelper.delete(key: "com.sqlexplorer.user-email")
        KeychainHelper.delete(key: "com.sqlexplorer.account-id")
        KeychainHelper.delete(key: "com.sqlexplorer.msal-cache")
        print("[Auth] Signed out — all data cleared")
    }

    // MARK: - SQL Token

    func getSQLToken() async -> String? {
        guard let app = application, let account else { return nil }

        do {
            let params = MSALSilentTokenParameters(scopes: Self.sqlScopes, account: account)
            return try await app.acquireTokenSilent(with: params).accessToken
        } catch {
            // Interactive fallback
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

            if let first = subscriptions.first {
                selectedSubscription = first
                await discoverDatabases(subscriptionId: first.id, subscriptionName: first.name)
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
