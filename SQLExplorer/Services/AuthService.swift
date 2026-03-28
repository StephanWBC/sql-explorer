import Foundation
import MSAL

/// Entra ID authentication using MSAL.Swift
/// Uses ASWebAuthenticationSession — system-managed, always private, Keychain-cached
@MainActor
class AuthService: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String = ""
    @Published var errorMessage: String?

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
            application = try MSALPublicClientApplication(configuration: config)
        } catch {
            errorMessage = "MSAL setup failed: \(error.localizedDescription)"
        }
    }

    /// Try to restore session from Keychain-cached tokens
    func tryRestoreSession() async {
        guard let app = application else { return }

        do {
            let accounts = try app.allAccounts()
            guard let account = accounts.first else { return }

            self.account = account

            let silentParams = MSALSilentTokenParameters(scopes: Self.armScopes, account: account)
            let result = try await app.acquireTokenSilent(with: silentParams)

            armAccessToken = result.accessToken
            userEmail = account.username ?? "Signed in"
            isSignedIn = true
        } catch {
            // Token expired or no cached account — user needs to sign in interactively
            isSignedIn = false
        }
    }

    /// Interactive sign-in — opens system auth session (always private, no Chrome hacking)
    func signIn() async {
        guard let app = application else { return }

        do {
            let params = MSALInteractiveTokenParameters(scopes: Self.armScopes)
            // ASWebAuthenticationSession handles the browser — always a private session
            params.promptType = .selectAccount

            let result = try await app.acquireToken(with: params)

            account = result.account
            armAccessToken = result.accessToken
            userEmail = result.account.username ?? "Signed in"
            isSignedIn = true
            errorMessage = nil
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isSignedIn = false
        }
    }

    /// Get ARM access token for Azure Resource Manager API calls
    func getARMToken() async -> String? {
        guard let app = application, let account else { return nil }

        do {
            let params = MSALSilentTokenParameters(scopes: Self.armScopes, account: account)
            let result = try await app.acquireTokenSilent(with: params)
            armAccessToken = result.accessToken
            return result.accessToken
        } catch {
            return armAccessToken  // Return cached if refresh fails
        }
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

    func signOut() {
        guard let app = application, let account else { return }
        try? app.remove(account)
        self.account = nil
        armAccessToken = nil
        userEmail = ""
        isSignedIn = false
    }
}
