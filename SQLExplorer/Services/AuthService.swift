import Foundation
import MSAL

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
    private static let tokenFile = storeDir.appendingPathComponent("refresh-token.json")
    private static let emailFile = storeDir.appendingPathComponent("auth-email.txt")
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

    // MARK: - Session Restore (OAuth2 refresh_token grant — no MSAL needed)

    func tryRestoreSession() async {
        // Check if user ever signed in
        guard let savedEmail = loadEmail() else {
            print("[Auth] No saved email — first launch")
            return
        }
        userEmail = savedEmail
        print("[Auth] Found saved session for: \(savedEmail)")

        // Try direct OAuth2 token refresh from saved refresh token
        if await refreshTokenFromFile(scope: "https://management.azure.com/.default offline_access") {
            isSignedIn = true
            print("[Auth] ✅ Session restored via OAuth2 refresh_token grant")
            await discoverSubscriptions()
            return
        }

        // Refresh failed — token expired or revoked
        print("[Auth] Token refresh failed — user must re-authenticate")
        errorMessage = "Session expired. Please sign in again."
        isSignedIn = false
    }

    /// Use saved refresh_token to get a new access_token via HTTP POST
    private func refreshTokenFromFile(scope: String) async -> Bool {
        guard let saved = loadTokenData(),
              let refreshToken = saved["refresh_token"] else {
            print("[Auth] No saved refresh token")
            return false
        }

        print("[Auth] Attempting OAuth2 refresh_token grant...")

        let tokenURL = URL(string: "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = [
            "client_id=\(Self.clientId)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "scope=\(scope)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            print("[Auth] Token endpoint responded: \(httpResponse?.statusCode ?? 0)")

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error_description"] as? String {
                    print("[Auth] Token error: \(error)")
                }
                return false
            }

            armAccessToken = accessToken

            // Save new refresh token (they rotate)
            if let newRefresh = json["refresh_token"] as? String {
                saveTokenData(refreshToken: newRefresh)
                print("[Auth] Saved rotated refresh token")
            }

            return true
        } catch {
            print("[Auth] HTTP refresh failed: \(error)")
            return false
        }
    }

    // MARK: - Interactive Sign-In (MSAL — only used once)

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

            // CRITICAL: extract refresh token from MSAL's REAL Keychain entry and save to file
            saveEmail(userEmail)
            extractAndSaveRefreshToken()
            print("[Auth] ✅ Signed in: \(userEmail)")

            await discoverSubscriptions()
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isSignedIn = false
        }
    }

    /// Extract refresh token from MSAL's actual Keychain cache
    /// MSAL stores at service="Microsoft Credentials", NOT "SqlExplorer"
    private func extractAndSaveRefreshToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Microsoft Credentials",
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            print("[Auth] Could not read MSAL's real Keychain cache (status=\(status))")
            // Fallback: try the other known service name
            extractFromAlternateKeychainEntry()
            return
        }

        for item in items {
            guard let data = item[kSecValueData as String] as? Data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let refreshTokens = json["RefreshToken"] as? [String: Any] else { continue }

            for (_, value) in refreshTokens {
                guard let tokenInfo = value as? [String: Any],
                      let clientId = tokenInfo["client_id"] as? String,
                      clientId == Self.clientId,
                      let secret = tokenInfo["secret"] as? String else { continue }

                saveTokenData(refreshToken: secret)
                print("[Auth] ✅ Extracted refresh token from MSAL cache (Microsoft Credentials)")
                return
            }
        }

        print("[Auth] No matching refresh token found in Microsoft Credentials")
        extractFromAlternateKeychainEntry()
    }

    /// Try alternate Keychain service names MSAL might use
    private func extractFromAlternateKeychainEntry() {
        // MSAL might also store under different service names depending on version
        let alternateServices = ["SqlExplorer", "com.sqlexplorer.app", "MSALCache"]

        for service in alternateServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let items = result as? [[String: Any]] else { continue }

            for item in items {
                guard let data = item[kSecValueData as String] as? Data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let refreshTokens = json["RefreshToken"] as? [String: Any] else { continue }

                for (_, value) in refreshTokens {
                    guard let tokenInfo = value as? [String: Any],
                          let secret = tokenInfo["secret"] as? String else { continue }

                    saveTokenData(refreshToken: secret)
                    print("[Auth] ✅ Extracted refresh token from '\(service)'")
                    return
                }
            }
        }
        print("[Auth] ⚠️ Could not find refresh token in any Keychain entry")
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
        try? FileManager.default.removeItem(at: Self.tokenFile)
        try? FileManager.default.removeItem(at: Self.emailFile)
    }

    // MARK: - SQL Token

    func getSQLToken() async -> String? {
        // Try direct refresh with SQL scope
        guard let saved = loadTokenData(),
              let refreshToken = saved["refresh_token"] else { return nil }

        let tokenURL = URL(string: "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = [
            "client_id=\(Self.clientId)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "scope=https://database.windows.net/.default offline_access",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else { return nil }

            // Save rotated refresh token
            if let newRefresh = json["refresh_token"] as? String {
                saveTokenData(refreshToken: newRefresh)
            }
            return accessToken
        } catch {
            return nil
        }
    }

    // MARK: - File Persistence

    private func saveTokenData(refreshToken: String) {
        let data: [String: String] = ["refresh_token": refreshToken, "client_id": Self.clientId]
        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            try? jsonData.write(to: Self.tokenFile, options: .atomic)
        }
    }

    private func loadTokenData() -> [String: String]? {
        guard let data = try? Data(contentsOf: Self.tokenFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return json
    }

    private func saveEmail(_ email: String) {
        try? FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
        try? email.write(to: Self.emailFile, atomically: true, encoding: .utf8)
    }

    private func loadEmail() -> String? {
        try? String(contentsOf: Self.emailFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

            // Select saved default subscription, or first
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
