import Foundation

enum ERDService {

    static func loadSchema(connectionManager: ConnectionManager, connectionId: UUID, databaseName: String) async throws -> ([ERDTable], [ERDRelationship]) {
        // Query 1: All tables with columns, PK, FK info
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
            ORDER BY s.name, t.name, c.column_id
            """

        // Query 2: Foreign key relationships
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

        // Build tables from column result
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

        // Layout tables in a grid
        let tables = layoutTables(tableMap)

        // Build relationships
        var relationships: [ERDRelationship] = []
        for row in fkResult.rows {
            relationships.append(ERDRelationship(
                name: row[4],
                fromTable: row[0],
                fromColumn: row[1],
                toTable: row[2],
                toColumn: row[3]
            ))
        }

        return (tables, relationships)
    }

    private static func layoutTables(_ tableMap: [String: (schema: String, name: String, columns: [ERDColumn])]) -> [ERDTable] {
        let sorted = tableMap.sorted { $0.key < $1.key }
        let cols = max(Int(ceil(sqrt(Double(sorted.count)))), 1)
        let tableWidth: CGFloat = 240
        let tableBaseHeight: CGFloat = 60
        let rowHeight: CGFloat = 18
        let spacing: CGFloat = 40

        var tables: [ERDTable] = []
        for (index, entry) in sorted.enumerated() {
            let gridCol = index % cols
            let gridRow = index / cols
            let estimatedHeight = tableBaseHeight + CGFloat(entry.value.columns.count) * rowHeight
            _ = estimatedHeight // used conceptually for spacing
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
