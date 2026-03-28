import Foundation
import CFreeTDS
import CFreeTDSShim

/// Executes SQL queries against connected SQL Server instances
final class QueryExecutionService: @unchecked Sendable {
    nonisolated(unsafe) private let bridge = FreeTDSBridge.shared

    func executeQuery(_ sql: String, on proc: OpaquePointer) throws -> QueryResult {
        try bridge.executeQuery(sql, on: proc)
    }

    func executeNonQuery(_ sql: String, on proc: OpaquePointer) throws -> Int {
        try bridge.executeNonQuery(sql, on: proc)
    }
}
