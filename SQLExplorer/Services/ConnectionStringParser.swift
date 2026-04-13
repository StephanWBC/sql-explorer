import Foundation

/// Parses Microsoft SqlClient-style connection strings into a `ConnectionInfo`
/// draft. Handles the keys we care about — anything else is silently ignored.
///
/// Supported keys (case-insensitive, both spellings):
/// - `Server` / `Data Source` / `Address` / `Addr` / `Network Address`
/// - `Initial Catalog` / `Database`
/// - `User Id` / `UID` / `User`
/// - `Password` / `PWD`
/// - `Port` (custom; not native SqlClient — also accepted via `Server=host,port`)
/// - `Encrypt`
/// - `TrustServerCertificate` / `Trust Server Certificate`
/// - `Authentication` (e.g. "Active Directory Interactive" → entraIdInteractive)
struct ConnectionStringParser {
    enum ParseError: LocalizedError {
        case missingServer
        case empty

        var errorDescription: String? {
            switch self {
            case .missingServer: return "Connection string is missing 'Server' / 'Data Source'."
            case .empty:         return "Connection string is empty."
            }
        }
    }

    static func parse(_ raw: String) throws -> ConnectionInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }

        // Split on `;`, ignoring empty segments. Each segment is `Key = Value`.
        var pairs: [String: String] = [:]
        for segment in trimmed.split(separator: ";", omittingEmptySubsequences: true) {
            let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes if present (e.g. Password="my;value")
            let unquoted: String
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                unquoted = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                unquoted = String(value.dropFirst().dropLast())
            } else {
                unquoted = value
            }
            pairs[key] = unquoted
        }

        // Server (with optional ,port suffix and optional tcp: prefix)
        let serverKeys = ["server", "data source", "address", "addr", "network address"]
        guard let serverRaw = serverKeys.compactMap({ pairs[$0] }).first, !serverRaw.isEmpty else {
            throw ParseError.missingServer
        }

        var serverHost = serverRaw
        var port: Int = 1433

        // Strip "tcp:" prefix
        if serverHost.lowercased().hasPrefix("tcp:") {
            serverHost = String(serverHost.dropFirst(4))
        }

        // Split host,port
        if let commaIdx = serverHost.firstIndex(of: ",") {
            let portStr = serverHost[serverHost.index(after: commaIdx)...].trimmingCharacters(in: .whitespaces)
            if let p = Int(portStr) { port = p }
            serverHost = String(serverHost[..<commaIdx]).trimmingCharacters(in: .whitespaces)
        }

        // Explicit Port= overrides server-suffix port
        if let portStr = pairs["port"], let p = Int(portStr) {
            port = p
        }

        let database = pairs["initial catalog"] ?? pairs["database"] ?? "master"
        let username = pairs["user id"] ?? pairs["uid"] ?? pairs["user"]
        let password = pairs["password"] ?? pairs["pwd"]

        // Auth type
        let authType: ConnectionAuthType
        if let authValue = pairs["authentication"]?.lowercased() {
            if authValue.contains("active directory") {
                authType = .entraIdInteractive
            } else {
                authType = .sqlAuthentication
            }
        } else if username != nil && password != nil {
            authType = .sqlAuthentication
        } else {
            authType = .sqlAuthentication
        }

        let encrypt = parseBool(pairs["encrypt"]) ?? true
        let trustCert = parseBool(pairs["trustservercertificate"])
            ?? parseBool(pairs["trust server certificate"])
            ?? true

        return ConnectionInfo(
            name: "\(database) — \(serverHost)",
            server: serverHost,
            port: port,
            database: database,
            authType: authType,
            username: username,
            password: password,
            trustServerCertificate: trustCert,
            encrypt: encrypt
        )
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let v = value?.lowercased() else { return nil }
        switch v {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }
}
