import Foundation
import CFreeTDS
import CFreeTDSShim

/// Low-level Swift wrapper around FreeTDS db-lib for SQL Server connectivity
final class FreeTDSBridge: @unchecked Sendable {
    private var process: OpaquePointer?

    static let shared = FreeTDSBridge()

    private init() {
        dbinit()
        swift_install_error_handlers()
    }

    deinit {
        dbexit()
    }

    /// Open a connection to SQL Server
    func connect(server: String, port: Int, database: String, username: String, password: String) throws -> OpaquePointer {
        let login = dblogin()!

        swift_DBSETLUSER(login, username)
        swift_DBSETLPWD(login, password)
        swift_DBSETLAPP(login, "SQLExplorer")
        dbsetlversion(login, BYTE(DBVERSION_74))

        let hostPort = "\(server):\(port)"
        guard let proc = dbopen(login, hostPort) else {
            dbloginfree(login)
            throw FreeTDSError.connectionFailed("Could not connect to \(hostPort)")
        }

        dbloginfree(login)

        // Switch to requested database
        if database != "master" && !database.isEmpty {
            if dbuse(proc, database) == FAIL {
                dbclose(proc)
                throw FreeTDSError.connectionFailed("Could not switch to database '\(database)'")
            }
        }

        return proc
    }

    /// Execute a SQL query and return results
    func executeQuery(_ sql: String, on proc: OpaquePointer) throws -> QueryResult {
        let startTime = DispatchTime.now()

        guard dbcmd(proc, sql) == SUCCEED else {
            throw FreeTDSError.queryFailed("Failed to send command")
        }

        guard dbsqlexec(proc) == SUCCEED else {
            let msg = getLastError(proc)
            throw FreeTDSError.queryFailed(msg ?? "Query execution failed")
        }

        var result = QueryResult()
        var messages: [String] = []

        // Process result sets
        while dbresults(proc) == SUCCEED {
            let colCount = Int(dbnumcols(proc))
            if colCount == 0 { continue }

            // Build column metadata
            var columns: [QueryResultColumn] = []
            for i in 1...colCount {
                let namePtr = dbcolname(proc, Int32(i))
                let name = namePtr != nil ? String(cString: namePtr!) : "Column\(i)"
                let typeId = dbcoltype(proc, Int32(i))
                let typeName = String(cString: dbprtype(typeId))
                columns.append(QueryResultColumn(id: i - 1, name: name, dataType: typeName))
            }
            result.columns = columns

            // Fetch rows
            var rows: [[String]] = []
            while dbnextrow(proc) != NO_MORE_ROWS {
                var row: [String] = []
                for i in 1...colCount {
                    let dataPtr = dbdata(proc, Int32(i))
                    let dataLen = dbdatlen(proc, Int32(i))

                    if dataPtr == nil || dataLen == 0 {
                        row.append("NULL")
                    } else {
                        let colType = dbcoltype(proc, Int32(i))
                        row.append(convertToString(dataPtr!, length: Int(dataLen), type: colType))
                    }
                }
                rows.append(row)
            }
            result.rows = rows
        }

        let endTime = DispatchTime.now()
        result.elapsedMs = Int64(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        result.rowsAffected = Int(dbcount(proc))

        return result
    }

    /// Execute a non-query SQL statement (INSERT, UPDATE, DELETE)
    func executeNonQuery(_ sql: String, on proc: OpaquePointer) throws -> Int {
        guard dbcmd(proc, sql) == SUCCEED else {
            throw FreeTDSError.queryFailed("Failed to send command")
        }
        guard dbsqlexec(proc) == SUCCEED else {
            let msg = getLastError(proc)
            throw FreeTDSError.queryFailed(msg ?? "Execution failed")
        }

        // Consume results
        while dbresults(proc) != NO_MORE_RESULTS {}

        return Int(dbcount(proc))
    }

    /// Close a connection
    func disconnect(_ proc: OpaquePointer) {
        dbclose(proc)
    }

    // MARK: - Private helpers

    private func convertToString(_ data: UnsafePointer<BYTE>, length: Int, type: Int32) -> String {
        // Buffer for conversion
        var buf = [BYTE](repeating: 0, count: 256)
        let converted = dbconvert(nil, type, data, Int32(length), Int32(SYBCHAR), &buf, Int32(buf.count - 1))

        if converted > 0 {
            buf[Int(converted)] = 0
            return String(cString: buf.map { CChar(bitPattern: $0) })
        }

        // Fallback: raw bytes to string
        return Data(bytes: data, count: length)
            .map { String(format: "%c", $0) }
            .joined()
    }

    private func getLastError(_ proc: OpaquePointer) -> String? {
        defer { swift_clear_last_error() }
        guard let cStr = swift_get_last_error() else { return nil }
        return String(cString: cStr)
    }
}

enum FreeTDSError: LocalizedError {
    case connectionFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .queryFailed(let msg): return msg
        }
    }
}
