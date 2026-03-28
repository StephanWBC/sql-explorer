import Foundation
import CFreeTDS
import CFreeTDSShim

/// Manages active SQL Server connections via FreeTDS
/// All FreeTDS operations happen on a dedicated serial queue to avoid concurrency issues
@MainActor
class ConnectionManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var activeConnectionIds: Set<UUID> = []

    // Store connection processes — accessed only via the serial queue
    nonisolated(unsafe) private var processes: [UUID: OpaquePointer] = [:]
    nonisolated(unsafe) private var connectionInfos: [UUID: ConnectionInfo] = [:]
    private let queue = DispatchQueue(label: "com.sqlexplorer.freetds", qos: .userInitiated)

    func connect(_ info: ConnectionInfo) async throws -> UUID {
        let connId = info.id
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
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
                            continuation.resume(returning: .failure(FreeTDSError.connectionFailed("Could not switch to database '\(info.database)'")))
                            return
                        }
                    }

                    self.processes[connId] = proc
                    self.connectionInfos[connId] = info
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }

        switch result {
        case .success:
            activeConnectionIds.insert(connId)
            isConnected = true
            return connId
        case .failure(let error):
            throw error
        }
    }

    func disconnect(_ connectionId: UUID) {
        queue.async { [self] in
            if let proc = processes.removeValue(forKey: connectionId) {
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

    /// Execute a query on the FreeTDS serial queue
    func executeQuery(_ sql: String, connectionId: UUID) async throws -> QueryResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let proc = processes[connectionId] else {
                    continuation.resume(throwing: FreeTDSError.connectionFailed("Connection not found"))
                    return
                }
                do {
                    let result = try FreeTDSBridge.shared.executeQuery(sql, on: proc)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func testConnection(_ info: ConnectionInfo) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let login = dblogin()!
                swift_DBSETLUSER(login, info.username ?? "")
                swift_DBSETLPWD(login, info.password ?? "")
                swift_DBSETLAPP(login, "SQLExplorer")
                dbsetlversion(login, BYTE(DBVERSION_74))

                let hostPort = "\(info.server):\(info.port)"
                guard let proc = dbopen(login, hostPort) else {
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
}
