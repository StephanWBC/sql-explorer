import Foundation
import CODBC

/// ODBC bridge for SQL Server — supports Azure AD access token authentication
/// Uses Microsoft ODBC Driver 18 which handles token-based auth natively
final class ODBCBridge: @unchecked Sendable {
    static let shared = ODBCBridge()

    private var env: SQLHENV?

    private init() {
        var e: SQLHENV?
        SQLAllocHandle(Int16(SQL_HANDLE_ENV), nil, &e)
        if let e {
            SQLSetEnvAttr(e, Int32(SQL_ATTR_ODBC_VERSION), SQLPOINTER(bitPattern: Int(SQL_OV_ODBC3)), 0)
        }
        env = e
    }

    deinit {
        if let env { SQLFreeHandle(Int16(SQL_HANDLE_ENV), env) }
    }

    /// Connect using Azure AD access token
    func connectWithToken(server: String, database: String, accessToken: String) throws -> ODBCConnection {
        guard let env else { throw ODBCError.envFailed }

        var dbc: SQLHDBC?
        SQLAllocHandle(Int16(SQL_HANDLE_DBC), env, &dbc)
        guard let dbc else { throw ODBCError.allocFailed }

        // Build connection string for MS ODBC Driver 18 with access token
        let connStr = "Driver={ODBC Driver 18 for SQL Server};" +
            "Server=\(server);" +
            "Database=\(database);" +
            "Encrypt=yes;" +
            "TrustServerCertificate=yes;"

        // Set the access token attribute (SQL_COPT_SS_ACCESS_TOKEN = 1256)
        let tokenData = accessToken.data(using: .utf8)!
        // MS ODBC Driver expects the token as a struct: 4-byte length + UTF-16LE token data
        let utf16Token = accessToken.data(using: .utf16LittleEndian)!
        var tokenStruct = Data()
        var len = UInt32(utf16Token.count)
        tokenStruct.append(Data(bytes: &len, count: 4))
        tokenStruct.append(utf16Token)

        let tokenResult = tokenStruct.withUnsafeBytes { ptr in
            SQLSetConnectAttr(dbc, 1256, UnsafeMutableRawPointer(mutating: ptr.baseAddress), Int32(tokenStruct.count))
        }

        if tokenResult != Int16(SQL_SUCCESS) && tokenResult != Int16(SQL_SUCCESS_WITH_INFO) {
            let err = getError(handleType: Int16(SQL_HANDLE_DBC), handle: dbc)
            SQLFreeHandle(Int16(SQL_HANDLE_DBC), dbc)
            throw ODBCError.connectionFailed("Token set failed: \(err)")
        }

        // Connect
        var connStrOut = [SQLCHAR](repeating: 0, count: 1024)
        var connStrOutLen: SQLSMALLINT = 0

        let result = connStr.withCString { cstr in
            SQLDriverConnect(dbc, nil,
                           UnsafeMutablePointer(mutating: cstr).withMemoryRebound(to: UInt8.self, capacity: connStr.count) { $0 },
                           Int16(connStr.count),
                           &connStrOut, Int16(connStrOut.count), &connStrOutLen,
                           UInt16(SQL_DRIVER_NOPROMPT))
        }

        if result != Int16(SQL_SUCCESS) && result != Int16(SQL_SUCCESS_WITH_INFO) {
            let err = getError(handleType: Int16(SQL_HANDLE_DBC), handle: dbc)
            SQLFreeHandle(Int16(SQL_HANDLE_DBC), dbc)
            throw ODBCError.connectionFailed(err)
        }

        return ODBCConnection(dbc: dbc)
    }

    /// Connect using SQL Auth (username/password)
    func connectWithPassword(server: String, port: Int, database: String, username: String, password: String) throws -> ODBCConnection {
        guard let env else { throw ODBCError.envFailed }

        var dbc: SQLHDBC?
        SQLAllocHandle(Int16(SQL_HANDLE_DBC), env, &dbc)
        guard let dbc else { throw ODBCError.allocFailed }

        let connStr = "Driver={ODBC Driver 18 for SQL Server};" +
            "Server=\(server),\(port);" +
            "Database=\(database);" +
            "UID=\(username);" +
            "PWD=\(password);" +
            "Encrypt=yes;" +
            "TrustServerCertificate=yes;"

        var connStrOut = [SQLCHAR](repeating: 0, count: 1024)
        var connStrOutLen: SQLSMALLINT = 0

        let result = connStr.withCString { cstr in
            SQLDriverConnect(dbc, nil,
                           UnsafeMutablePointer(mutating: cstr).withMemoryRebound(to: UInt8.self, capacity: connStr.count) { $0 },
                           Int16(connStr.count),
                           &connStrOut, Int16(connStrOut.count), &connStrOutLen,
                           UInt16(SQL_DRIVER_NOPROMPT))
        }

        if result != Int16(SQL_SUCCESS) && result != Int16(SQL_SUCCESS_WITH_INFO) {
            let err = getError(handleType: Int16(SQL_HANDLE_DBC), handle: dbc)
            SQLFreeHandle(Int16(SQL_HANDLE_DBC), dbc)
            throw ODBCError.connectionFailed(err)
        }

        return ODBCConnection(dbc: dbc)
    }

    private func getError(handleType: SQLSMALLINT, handle: SQLHANDLE?) -> String {
        var sqlState = [SQLCHAR](repeating: 0, count: 6)
        var nativeError: SQLINTEGER = 0
        var message = [SQLCHAR](repeating: 0, count: 1024)
        var messageLen: SQLSMALLINT = 0

        SQLGetDiagRec(handleType, handle, 1, &sqlState, &nativeError,
                      &message, Int16(message.count), &messageLen)

        return String(cString: message.map { CChar(bitPattern: $0) })
    }
}

/// Wraps an ODBC connection handle
class ODBCConnection {
    let dbc: SQLHDBC

    init(dbc: SQLHDBC) {
        self.dbc = dbc
    }

    deinit {
        SQLDisconnect(dbc)
        SQLFreeHandle(Int16(SQL_HANDLE_DBC), dbc)
    }

    func executeQuery(_ sql: String, maxRows: Int = 10000) throws -> QueryResult {
        var stmt: SQLHSTMT?
        SQLAllocHandle(Int16(SQL_HANDLE_STMT), dbc, &stmt)
        guard let stmt else { throw ODBCError.allocFailed }
        defer { SQLFreeHandle(Int16(SQL_HANDLE_STMT), stmt) }

        // Set query timeout to 30 seconds
        SQLSetStmtAttr(stmt, Int32(SQL_ATTR_QUERY_TIMEOUT), SQLPOINTER(bitPattern: 30), 0)

        let startTime = DispatchTime.now()

        let result = sql.withCString { cstr in
            SQLExecDirect(stmt,
                         UnsafeMutablePointer(mutating: cstr).withMemoryRebound(to: UInt8.self, capacity: sql.count) { $0 },
                         Int32(SQL_NTS))
        }

        if result != Int16(SQL_SUCCESS) && result != Int16(SQL_SUCCESS_WITH_INFO) {
            var sqlState = [SQLCHAR](repeating: 0, count: 6)
            var nativeError: SQLINTEGER = 0
            var message = [SQLCHAR](repeating: 0, count: 1024)
            var messageLen: SQLSMALLINT = 0
            SQLGetDiagRec(Int16(SQL_HANDLE_STMT), stmt, 1, &sqlState, &nativeError, &message, Int16(message.count), &messageLen)
            throw ODBCError.queryFailed(String(cString: message.map { CChar(bitPattern: $0) }))
        }

        // Get column count
        var colCount: SQLSMALLINT = 0
        SQLNumResultCols(stmt, &colCount)

        if colCount == 0 {
            var rowCount: SQLLEN = 0
            SQLRowCount(stmt, &rowCount)
            let elapsed = Int64(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            return QueryResult(rowsAffected: Int(rowCount), elapsedMs: elapsed)
        }

        // Build columns
        var columns: [QueryResultColumn] = []
        for i in 1...Int(colCount) {
            var colName = [SQLCHAR](repeating: 0, count: 256)
            var nameLen: SQLSMALLINT = 0
            var dataType: SQLSMALLINT = 0
            var colSize: SQLULEN = 0
            var decimalDigits: SQLSMALLINT = 0
            var nullable: SQLSMALLINT = 0

            SQLDescribeCol(stmt, SQLUSMALLINT(i), &colName, Int16(colName.count), &nameLen,
                          &dataType, &colSize, &decimalDigits, &nullable)

            let name = String(cString: colName.map { CChar(bitPattern: $0) })
            columns.append(QueryResultColumn(id: i - 1, name: name, dataType: "varchar"))
        }

        // Fetch rows (capped at maxRows to prevent memory exhaustion)
        var rows: [[String]] = []
        while SQLFetch(stmt) == Int16(SQL_SUCCESS) && rows.count < maxRows {
            var row: [String] = []
            for i in 1...Int(colCount) {
                var value = [SQLCHAR](repeating: 0, count: 4096)
                var indicator: SQLLEN = 0
                SQLGetData(stmt, SQLUSMALLINT(i), Int16(SQL_C_CHAR), &value, SQLLEN(value.count), &indicator)

                if indicator == Int(SQL_NULL_DATA) {
                    row.append("NULL")
                } else {
                    row.append(String(cString: value.map { CChar(bitPattern: $0) }))
                }
            }
            rows.append(row)
        }

        let elapsed = Int64(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        return QueryResult(columns: columns, rows: rows, rowsAffected: rows.count, elapsedMs: elapsed)
    }
}

enum ODBCError: LocalizedError {
    case envFailed
    case allocFailed
    case connectionFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .envFailed: return "ODBC environment setup failed"
        case .allocFailed: return "ODBC handle allocation failed"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .queryFailed(let msg): return msg
        }
    }
}
