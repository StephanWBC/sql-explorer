namespace SqlStudio.Core.DataAccess;

public static class SystemTableQueries
{
    public const string GetDatabases = """
        SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name
        """;

    public const string GetTables = """
        SELECT s.name AS SchemaName, t.name AS TableName,
               SUM(p.rows) AS RowCount
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        LEFT JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
        GROUP BY s.name, t.name
        ORDER BY s.name, t.name
        """;

    public const string GetViews = """
        SELECT s.name AS SchemaName, v.name AS ViewName
        FROM sys.views v
        INNER JOIN sys.schemas s ON v.schema_id = s.schema_id
        WHERE v.is_ms_shipped = 0
        ORDER BY s.name, v.name
        """;

    public const string GetStoredProcedures = """
        SELECT s.name AS SchemaName, p.name AS ProcedureName
        FROM sys.procedures p
        INNER JOIN sys.schemas s ON p.schema_id = s.schema_id
        WHERE p.is_ms_shipped = 0
        ORDER BY s.name, p.name
        """;

    public const string GetFunctions = """
        SELECT s.name AS SchemaName, o.name AS FunctionName, o.type_desc AS TypeDescription
        FROM sys.objects o
        INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
        WHERE o.type IN ('FN', 'IF', 'TF') AND o.is_ms_shipped = 0
        ORDER BY s.name, o.name
        """;

    public const string GetColumns = """
        SELECT c.name AS ColumnName, t.name AS DataType,
               c.max_length AS MaxLength, c.precision, c.scale,
               c.is_nullable AS IsNullable, c.is_identity AS IsIdentity,
               CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPrimaryKey,
               c.column_id AS OrdinalPosition,
               dc.definition AS DefaultValue
        FROM sys.columns c
        INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
        LEFT JOIN (
            SELECT ic.object_id, ic.column_id
            FROM sys.index_columns ic
            INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            WHERE i.is_primary_key = 1
        ) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id
        LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
        WHERE c.object_id = OBJECT_ID(@objectName)
        ORDER BY c.column_id
        """;

    public const string GetIndexes = """
        SELECT i.name AS IndexName, i.type_desc AS IndexType,
               i.is_unique AS IsUnique, i.is_primary_key AS IsPrimaryKey,
               STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS Columns
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID(@objectName) AND i.name IS NOT NULL
        GROUP BY i.name, i.type_desc, i.is_unique, i.is_primary_key
        ORDER BY i.name
        """;

    public const string GetForeignKeys = """
        SELECT fk.name AS ForeignKeyName,
               rs.name AS ReferencedSchema,
               rt.name AS ReferencedTable,
               STRING_AGG(pc.name, ', ') WITHIN GROUP (ORDER BY fkc.constraint_column_id) AS Columns,
               STRING_AGG(rc.name, ', ') WITHIN GROUP (ORDER BY fkc.constraint_column_id) AS ReferencedColumns
        FROM sys.foreign_keys fk
        INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN sys.columns pc ON fkc.parent_object_id = pc.object_id AND fkc.parent_column_id = pc.column_id
        INNER JOIN sys.columns rc ON fkc.referenced_object_id = rc.object_id AND fkc.referenced_column_id = rc.column_id
        INNER JOIN sys.tables rt ON fkc.referenced_object_id = rt.object_id
        INNER JOIN sys.schemas rs ON rt.schema_id = rs.schema_id
        WHERE fk.parent_object_id = OBJECT_ID(@objectName)
        GROUP BY fk.name, rs.name, rt.name
        ORDER BY fk.name
        """;

    public const string GetObjectDefinition = """
        SELECT OBJECT_DEFINITION(OBJECT_ID(@objectName)) AS Definition
        """;

    public const string GetTableCreateScript = """
        SELECT
            'CREATE TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ' (' + CHAR(13) + CHAR(10) +
            STRING_AGG(
                '    ' + QUOTENAME(c.name) + ' ' +
                UPPER(tp.name) +
                CASE
                    WHEN tp.name IN ('varchar', 'nvarchar', 'char', 'nchar')
                        THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(CASE WHEN tp.name LIKE 'n%' THEN c.max_length / 2 ELSE c.max_length END AS VARCHAR) END + ')'
                    WHEN tp.name IN ('decimal', 'numeric')
                        THEN '(' + CAST(c.precision AS VARCHAR) + ', ' + CAST(c.scale AS VARCHAR) + ')'
                    ELSE ''
                END +
                CASE WHEN c.is_identity = 1 THEN ' IDENTITY(1,1)' ELSE '' END +
                CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END,
                ',' + CHAR(13) + CHAR(10)
            ) WITHIN GROUP (ORDER BY c.column_id) +
            CHAR(13) + CHAR(10) + ')' AS CreateScript
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.columns c ON t.object_id = c.object_id
        INNER JOIN sys.types tp ON c.user_type_id = tp.user_type_id
        WHERE t.object_id = OBJECT_ID(@objectName)
        GROUP BY s.name, t.name
        """;
}
