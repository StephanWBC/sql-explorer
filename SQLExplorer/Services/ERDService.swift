import Foundation

enum ERDService {

    static func listTables(connectionManager: ConnectionManager, connectionId: UUID) async throws -> [ERDTableEntry] {
        let sql = """
            SELECT s.name, t.name
            FROM sys.tables t
            JOIN sys.schemas s ON t.schema_id = s.schema_id
            ORDER BY s.name, t.name
            """
        let result = try await connectionManager.executeQuery(sql, connectionId: connectionId)
        return result.rows.map { ERDTableEntry(schema: $0[0], name: $0[1]) }
    }

    /// Load columns for a single table
    static func loadTableColumns(connectionManager: ConnectionManager, connectionId: UUID, schemaName: String, tableName: String) async throws -> [ERDColumn] {
        let sql = """
            SELECT c.name, tp.name AS DataType, c.max_length, c.precision, c.scale, c.is_nullable,
                   CASE WHEN ic.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPK,
                   CASE WHEN fkc.parent_column_id IS NOT NULL THEN 1 ELSE 0 END AS IsFK
            FROM sys.columns c
            JOIN sys.types tp ON c.user_type_id = tp.user_type_id
            LEFT JOIN sys.indexes i ON i.object_id = c.object_id AND i.is_primary_key = 1
            LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.column_id = c.column_id
            LEFT JOIN sys.foreign_key_columns fkc ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
            WHERE c.object_id = \(SQLEscaping.objectIdRef(schema: schemaName, table: tableName))
            ORDER BY c.column_id
            """
        let result = try await connectionManager.executeQuery(sql, connectionId: connectionId)
        return result.rows.map { row in
            let typeName = row[1]
            let maxLen = Int(row[2]) ?? 0
            let precision = Int(row[3]) ?? 0
            let scale = Int(row[4]) ?? 0

            var typeStr = typeName
            switch typeName.lowercased() {
            case "nvarchar", "nchar":
                typeStr = maxLen == -1 ? "\(typeName)(MAX)" : "\(typeName)(\(maxLen / 2))"
            case "varchar", "char", "varbinary":
                typeStr = maxLen == -1 ? "\(typeName)(MAX)" : "\(typeName)(\(maxLen))"
            case "decimal", "numeric":
                typeStr = "\(typeName)(\(precision),\(scale))"
            default: break
            }

            return ERDColumn(
                name: row[0], dataType: typeStr,
                isPrimaryKey: row[6] == "1",
                isForeignKey: row[7] == "1",
                isNullable: row[5] == "1" || row[5].lowercased() == "true"
            )
        }
    }

    /// Load FK relationships involving the given set of tables
    static func loadRelationships(connectionManager: ConnectionManager, connectionId: UUID, tableNames: Set<String>) async throws -> [ERDRelationship] {
        let sql = """
            SELECT
                OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id),
                COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
                OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id),
                COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id),
                fk.name
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
            """
        let result = try await connectionManager.executeQuery(sql, connectionId: connectionId)
        return result.rows.compactMap { row in
            let from = row[0], to = row[2]
            guard tableNames.contains(from) && tableNames.contains(to) else { return nil }
            return ERDRelationship(name: row[4], fromTable: from, fromColumn: row[1], toTable: to, toColumn: row[3])
        }
    }

    // MARK: - Cached FK support for related-table suggestions

    /// Fetch all foreign keys in the database (cached per ERD session)
    static func loadAllForeignKeys(connectionManager: ConnectionManager, connectionId: UUID) async throws -> [ForeignKeyRow] {
        let sql = """
            SELECT
                OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id),
                COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
                OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id),
                COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id),
                fk.name
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
            """
        let result = try await connectionManager.executeQuery(sql, connectionId: connectionId)
        return result.rows.map { row in
            ForeignKeyRow(parentTable: row[0], parentColumn: row[1],
                          referencedTable: row[2], referencedColumn: row[3],
                          constraintName: row[4])
        }
    }

    /// Derive on-canvas relationships from cached FK rows (pure function)
    static func filterRelationships(from allFKs: [ForeignKeyRow], tablesOnCanvas: Set<String>) -> [ERDRelationship] {
        allFKs.compactMap { fk in
            guard tablesOnCanvas.contains(fk.parentTable) && tablesOnCanvas.contains(fk.referencedTable) else { return nil }
            return ERDRelationship(name: fk.constraintName, fromTable: fk.parentTable,
                                   fromColumn: fk.parentColumn, toTable: fk.referencedTable,
                                   toColumn: fk.referencedColumn)
        }
    }

    /// Derive related tables not on canvas from cached FK rows (pure function)
    static func filterRelatedTables(from allFKs: [ForeignKeyRow], tablesOnCanvas: Set<String>) -> [ERDRelatedTable] {
        var results: [ERDRelatedTable] = []
        var seen: Set<String> = [] // "fullName|relatedTo|fkName" to deduplicate

        for fk in allFKs {
            let parentOnCanvas = tablesOnCanvas.contains(fk.parentTable)
            let refOnCanvas = tablesOnCanvas.contains(fk.referencedTable)

            // Skip if both on canvas (handled by relationships) or neither on canvas
            guard parentOnCanvas != refOnCanvas else { continue }
            // Skip self-referencing FKs
            guard fk.parentTable != fk.referencedTable else { continue }

            if parentOnCanvas && !refOnCanvas {
                // Canvas table's FK references this table (outgoing)
                let key = "\(fk.referencedTable)|\(fk.parentTable)|\(fk.constraintName)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let parts = fk.referencedTable.split(separator: ".", maxSplits: 1)
                guard parts.count == 2 else { continue }
                results.append(ERDRelatedTable(
                    schema: String(parts[0]), name: String(parts[1]),
                    relatedToTable: fk.parentTable, foreignKeyName: fk.constraintName,
                    columnName: fk.parentColumn, direction: .outgoing))
            } else {
                // This table's FK references a canvas table (incoming)
                let key = "\(fk.parentTable)|\(fk.referencedTable)|\(fk.constraintName)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let parts = fk.parentTable.split(separator: ".", maxSplits: 1)
                guard parts.count == 2 else { continue }
                results.append(ERDRelatedTable(
                    schema: String(parts[0]), name: String(parts[1]),
                    relatedToTable: fk.referencedTable, foreignKeyName: fk.constraintName,
                    columnName: fk.parentColumn, direction: .incoming))
            }
        }

        return results
    }
}
