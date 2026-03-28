import Foundation
import CFreeTDS
import CFreeTDSShim

/// Manages active SQL Server connections
/// Uses ODBC (MS Driver 18) for Entra ID, FreeTDS for SQL Auth
@MainActor
class ConnectionManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var activeConnectionIds: Set<UUID> = []

    nonisolated(unsafe) private var odbcConnections: [UUID: ODBCConnection] = [:]
    nonisolated(unsafe) private var freetdsProcesses: [UUID: OpaquePointer] = [:]
    nonisolated(unsafe) private var connectionInfos: [UUID: ConnectionInfo] = [:]
    private let queue = DispatchQueue(label: "com.sqlexplorer.db", qos: .userInitiated)

    func connect(_ info: ConnectionInfo) async throws -> UUID {
        let connId = info.id

        if info.authType == .entraIdInteractive {
            // ODBC with access token
            try await connectODBC(info)
        } else {
            // FreeTDS with username/password
            try await connectFreeTDS(info)
        }

        connectionInfos[connId] = info
        activeConnectionIds.insert(connId)
        isConnected = true
        return connId
    }

    private func connectODBC(_ info: ConnectionInfo) async throws {
        let result: Result<ODBCConnection, Error> = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let conn = try ODBCBridge.shared.connectWithToken(
                        server: info.server,
                        database: info.database,
                        accessToken: info.password ?? ""
                    )
                    continuation.resume(returning: .success(conn))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success(let conn):
            odbcConnections[info.id] = conn
        case .failure(let error):
            throw error
        }
    }

    private func connectFreeTDS(_ info: ConnectionInfo) async throws {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            queue.async { [self] in
                let login = dblogin()!
                swift_DBSETLUSER(login, info.username ?? "")
                swift_DBSETLPWD(login, info.password ?? "")
                swift_DBSETLAPP(login, "SQLExplorer")
                dbsetlversion(login, BYTE(DBVERSION_74))

                let hostPort = "\(info.server):\(info.port)"
                guard let proc = dbopen(login, hostPort) else {
                    dbloginfree(login)
                    continuation.resume(returning: .failure(FreeTDSError.connectionFailed("Could not connect to \(hostPort)")))
                    return
                }
                dbloginfree(login)

                if info.database != "master" && !info.database.isEmpty {
                    if dbuse(proc, info.database) == FAIL {
                        dbclose(proc)
                        continuation.resume(returning: .failure(FreeTDSError.connectionFailed("Could not switch to '\(info.database)'")))
                        return
                    }
                }

                self.freetdsProcesses[info.id] = proc
                continuation.resume(returning: .success(()))
            }
        }
        if case .failure(let error) = result { throw error }
    }

    func disconnect(_ connectionId: UUID) {
        queue.async { [self] in
            if let conn = odbcConnections.removeValue(forKey: connectionId) {
                _ = conn // deinit handles disconnect
            }
            if let proc = freetdsProcesses.removeValue(forKey: connectionId) {
                dbclose(proc)
            }
            connectionInfos.removeValue(forKey: connectionId)
        }
        activeConnectionIds.remove(connectionId)
        isConnected = !activeConnectionIds.isEmpty
    }

    func getConnectionInfo(_ id: UUID) -> ConnectionInfo? {
        connectionInfos[id]
    }

    /// Execute a query
    func executeQuery(_ sql: String, connectionId: UUID) async throws -> QueryResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                // Try ODBC first
                if let conn = odbcConnections[connectionId] {
                    do {
                        let result = try conn.executeQuery(sql)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                // FreeTDS fallback
                if let proc = freetdsProcesses[connectionId] {
                    do {
                        let result = try FreeTDSBridge.shared.executeQuery(sql, on: proc)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                continuation.resume(throwing: FreeTDSError.connectionFailed("Connection not found"))
            }
        }
    }

    func testConnection(_ info: ConnectionInfo) async -> Bool {
        do {
            if info.authType == .entraIdInteractive {
                let conn = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ODBCConnection, Error>) in
                    queue.async {
                        do {
                            let c = try ODBCBridge.shared.connectWithToken(
                                server: info.server, database: info.database, accessToken: info.password ?? "")
                            continuation.resume(returning: c)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                _ = conn // deinit disconnects
                return true
            } else {
                // FreeTDS test
                return await withCheckedContinuation { continuation in
                    queue.async {
                        let login = dblogin()!
                        swift_DBSETLUSER(login, info.username ?? "")
                        swift_DBSETLPWD(login, info.password ?? "")
                        swift_DBSETLAPP(login, "SQLExplorer")
                        dbsetlversion(login, BYTE(DBVERSION_74))
                        guard let proc = dbopen(login, "\(info.server):\(info.port)") else {
                            dbloginfree(login)
                            continuation.resume(returning: false)
                            return
                        }
                        dbloginfree(login)
                        dbclose(proc)
                        continuation.resume(returning: true)
                    }
                }
            }
        } catch {
            return false
        }
    }
}
