import Foundation
import CFreeTDS
import CFreeTDSShim

/// Queries sys.* catalog tables to build the Object Explorer tree
final class ObjectExplorerService: @unchecked Sendable {
    nonisolated(unsafe) private let bridge = FreeTDSBridge.shared

    func getDatabases(proc: OpaquePointer) throws -> [String] {
        let result = try bridge.executeQuery("SELECT name FROM sys.databases ORDER BY name", on: proc)
        return result.rows.map { $0[0] }
    }

    func getTables(proc: OpaquePointer, database: String) throws -> [(schema: String, name: String, rowCount: Int64)] {
        let sql = "USE \(SQLEscaping.bracketIdentifier(database)); SELECT s.name, t.name, ISNULL(p.rows, 0) FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id LEFT JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1) ORDER BY s.name, t.name"
        let result = try bridge.executeQuery(sql, on: proc)
        return result.rows.map { (schema: $0[0], name: $0[1], rowCount: Int64($0[2]) ?? 0) }
    }

    func getViews(proc: OpaquePointer, database: String) throws -> [(schema: String, name: String)] {
        let sql = "USE \(SQLEscaping.bracketIdentifier(database)); SELECT s.name, v.name FROM sys.views v JOIN sys.schemas s ON v.schema_id = s.schema_id ORDER BY s.name, v.name"
        let result = try bridge.executeQuery(sql, on: proc)
        return result.rows.map { (schema: $0[0], name: $0[1]) }
    }

    func getStoredProcedures(proc: OpaquePointer, database: String) throws -> [(schema: String, name: String)] {
        let sql = "USE \(SQLEscaping.bracketIdentifier(database)); SELECT s.name, p.name FROM sys.procedures p JOIN sys.schemas s ON p.schema_id = s.schema_id WHERE p.is_ms_shipped = 0 ORDER BY s.name, p.name"
        let result = try bridge.executeQuery(sql, on: proc)
        return result.rows.map { (schema: $0[0], name: $0[1]) }
    }

    func getFunctions(proc: OpaquePointer, database: String) throws -> [(schema: String, name: String, type: String)] {
        let sql = "USE \(SQLEscaping.bracketIdentifier(database)); SELECT s.name, o.name, o.type_desc FROM sys.objects o JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('FN', 'IF', 'TF') AND o.is_ms_shipped = 0 ORDER BY s.name, o.name"
        let result = try bridge.executeQuery(sql, on: proc)
        return result.rows.map { (schema: $0[0], name: $0[1], type: $0[2]) }
    }

    func getColumns(proc: OpaquePointer, database: String, schema: String, table: String) throws -> [(name: String, dataType: String, isNullable: Bool, isPK: Bool)] {
        let sql = "USE \(SQLEscaping.bracketIdentifier(database)); SELECT c.name, TYPE_NAME(c.user_type_id), c.is_nullable, CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END FROM sys.columns c JOIN sys.tables t ON c.object_id = t.object_id JOIN sys.schemas s ON t.schema_id = s.schema_id LEFT JOIN (SELECT ic.object_id, ic.column_id FROM sys.index_columns ic JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id WHERE i.is_primary_key = 1) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id WHERE s.name = \(SQLEscaping.quotedString(schema)) AND t.name = \(SQLEscaping.quotedString(table)) ORDER BY c.column_id"
        let result = try bridge.executeQuery(sql, on: proc)
        return result.rows.map { (name: $0[0], dataType: $0[1], isNullable: $0[2] == "1", isPK: $0[3] == "1") }
    }
}
