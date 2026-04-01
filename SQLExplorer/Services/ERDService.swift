import Foundation

enum ERDService {

    /// Fast: just fetch table names for the picker
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

    /// Load full schema (columns + FKs) for only the selected tables
    static func loadSchema(connectionManager: ConnectionManager, connectionId: UUID, tableNames: Set<String>) async throws -> ([ERDTable], [ERDRelationship]) {
        guard !tableNames.isEmpty else { return ([], []) }

        // Build a filter for the selected tables
        let tableFilter = tableNames.map { name -> String in
            let parts = name.split(separator: ".", maxSplits: 1)
            let schema = parts.count == 2 ? String(parts[0]) : "dbo"
            let table = parts.count == 2 ? String(parts[1]) : name
            return "(s.name = '\(schema)' AND t.name = '\(table)')"
        }.joined(separator: " OR ")

        // Query columns for selected tables only
        let columnSQL = """
            SELECT
                s.name AS SchemaName,
                t.name AS TableName,
                c.name AS ColumnName,
                tp.name AS DataType,
                c.max_length, c.precision, c.scale,
                c.is_nullable,
                CASE WHEN ic.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPK,
                CASE WHEN fkc.parent_column_id IS NOT NULL THEN 1 ELSE 0 END AS IsFK
            FROM sys.tables t
            JOIN sys.schemas s ON t.schema_id = s.schema_id
            JOIN sys.columns c ON c.object_id = t.object_id
            JOIN sys.types tp ON c.user_type_id = tp.user_type_id
            LEFT JOIN sys.indexes i ON i.object_id = t.object_id AND i.is_primary_key = 1
            LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.column_id = c.column_id
            LEFT JOIN sys.foreign_key_columns fkc ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
            WHERE \(tableFilter)
            ORDER BY s.name, t.name, c.column_id
            """

        // Query FK relationships between selected tables
        let fkSQL = """
            SELECT
                OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS FromTable,
                COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS FromColumn,
                OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS ToTable,
                COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS ToColumn,
                fk.name AS FKName
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
            """

        let colResult = try await connectionManager.executeQuery(columnSQL, connectionId: connectionId)
        let fkResult = try await connectionManager.executeQuery(fkSQL, connectionId: connectionId)

        // Build tables
        var tableMap: [String: (schema: String, name: String, columns: [ERDColumn])] = [:]

        for row in colResult.rows {
            let schemaName = row[0]
            let tableName = row[1]
            let colName = row[2]
            let typeName = row[3]
            let maxLen = Int(row[4]) ?? 0
            let precision = Int(row[5]) ?? 0
            let scale = Int(row[6]) ?? 0
            let nullable = row[7] == "1" || row[7].lowercased() == "true"
            let isPK = row[8] == "1"
            let isFK = row[9] == "1"

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

            let key = "\(schemaName).\(tableName)"
            let col = ERDColumn(name: colName, dataType: typeStr, isPrimaryKey: isPK, isForeignKey: isFK, isNullable: nullable)

            if tableMap[key] != nil {
                tableMap[key]!.columns.append(col)
            } else {
                tableMap[key] = (schema: schemaName, name: tableName, columns: [col])
            }
        }

        // Layout
        let tables = layoutTables(tableMap)

        // FK relationships — only between selected tables
        var relationships: [ERDRelationship] = []
        for row in fkResult.rows {
            let from = row[0], to = row[2]
            if tableNames.contains(from) && tableNames.contains(to) {
                relationships.append(ERDRelationship(
                    name: row[4], fromTable: from, fromColumn: row[1],
                    toTable: to, toColumn: row[3]
                ))
            }
        }

        return (tables, relationships)
    }

    private static func layoutTables(_ tableMap: [String: (schema: String, name: String, columns: [ERDColumn])]) -> [ERDTable] {
        let sorted = tableMap.sorted { $0.key < $1.key }
        let cols = max(Int(ceil(sqrt(Double(sorted.count)))), 1)
        let tableWidth: CGFloat = 240
        let spacing: CGFloat = 40

        var tables: [ERDTable] = []
        for (index, entry) in sorted.enumerated() {
            let gridCol = index % cols
            let gridRow = index / cols
            let x = CGFloat(gridCol) * (tableWidth + spacing) + 40
            let y = CGFloat(gridRow) * (200 + spacing) + 40

            tables.append(ERDTable(
                schema: entry.value.schema,
                name: entry.value.name,
                columns: entry.value.columns,
                position: CGPoint(x: x, y: y)
            ))
        }

        return tables
    }
}
