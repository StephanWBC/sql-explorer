using Microsoft.Data.SqlClient;
using SqlStudio.Core.DataAccess;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class ObjectExplorerService : IObjectExplorerService
{
    private readonly IConnectionManager _connectionManager;

    public ObjectExplorerService(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
    }

    public async Task<IReadOnlyList<string>> GetDatabasesAsync(Guid connectionId, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await using var cmd = new SqlCommand(SystemTableQueries.GetDatabases, connection);
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var databases = new List<string>();
        while (await reader.ReadAsync(ct))
            databases.Add(reader.GetString(0));

        return databases;
    }

    public async Task<IReadOnlyList<TableInfo>> GetTablesAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        var sql = schema != null
            ? SystemTableQueries.GetTables + " HAVING s.name = @schema"
            : SystemTableQueries.GetTables;

        await using var cmd = new SqlCommand(sql, connection);
        if (schema != null) cmd.Parameters.AddWithValue("@schema", schema);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var tables = new List<TableInfo>();
        while (await reader.ReadAsync(ct))
        {
            tables.Add(new TableInfo
            {
                Schema = reader.GetString(0),
                Name = reader.GetString(1),
                RowCount = reader.IsDBNull(2) ? 0 : reader.GetInt64(2)
            });
        }
        return tables;
    }

    public async Task<IReadOnlyList<ViewInfo>> GetViewsAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        await using var cmd = new SqlCommand(SystemTableQueries.GetViews, connection);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var views = new List<ViewInfo>();
        while (await reader.ReadAsync(ct))
        {
            views.Add(new ViewInfo
            {
                Schema = reader.GetString(0),
                Name = reader.GetString(1)
            });
        }
        return views;
    }

    public async Task<IReadOnlyList<StoredProcedureInfo>> GetStoredProceduresAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        await using var cmd = new SqlCommand(SystemTableQueries.GetStoredProcedures, connection);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var procs = new List<StoredProcedureInfo>();
        while (await reader.ReadAsync(ct))
        {
            procs.Add(new StoredProcedureInfo
            {
                Schema = reader.GetString(0),
                Name = reader.GetString(1)
            });
        }
        return procs;
    }

    public async Task<IReadOnlyList<FunctionInfo>> GetFunctionsAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        await using var cmd = new SqlCommand(SystemTableQueries.GetFunctions, connection);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var functions = new List<FunctionInfo>();
        while (await reader.ReadAsync(ct))
        {
            functions.Add(new FunctionInfo
            {
                Schema = reader.GetString(0),
                Name = reader.GetString(1),
                TypeDescription = reader.GetString(2)
            });
        }
        return functions;
    }

    public async Task<IReadOnlyList<ColumnInfo>> GetColumnsAsync(Guid connectionId, string database, string schema, string tableName, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        await using var cmd = new SqlCommand(SystemTableQueries.GetColumns, connection);
        cmd.Parameters.AddWithValue("@objectName", $"{schema}.{tableName}");
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var columns = new List<ColumnInfo>();
        while (await reader.ReadAsync(ct))
        {
            columns.Add(new ColumnInfo
            {
                Name = reader.GetString(0),
                DataType = reader.GetString(1),
                MaxLength = reader.GetInt16(2),
                Precision = reader.GetByte(3),
                Scale = reader.GetByte(4),
                IsNullable = reader.GetBoolean(5),
                IsIdentity = reader.GetBoolean(6),
                IsPrimaryKey = reader.GetInt32(7) == 1,
                OrdinalPosition = reader.GetInt32(8),
                DefaultValue = reader.IsDBNull(9) ? null : reader.GetString(9)
            });
        }
        return columns;
    }

    public async Task<IReadOnlyList<IndexInfo>> GetIndexesAsync(Guid connectionId, string database, string schema, string tableName, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        await using var cmd = new SqlCommand(SystemTableQueries.GetIndexes, connection);
        cmd.Parameters.AddWithValue("@objectName", $"{schema}.{tableName}");
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var indexes = new List<IndexInfo>();
        while (await reader.ReadAsync(ct))
        {
            indexes.Add(new IndexInfo
            {
                Name = reader.GetString(0),
                Type = reader.GetString(1),
                IsUnique = reader.GetBoolean(2),
                IsPrimaryKey = reader.GetBoolean(3),
                Columns = reader.GetString(4).Split(", ").ToList()
            });
        }
        return indexes;
    }

    public async Task<IReadOnlyList<ForeignKeyInfo>> GetForeignKeysAsync(Guid connectionId, string database, string schema, string tableName, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        await using var cmd = new SqlCommand(SystemTableQueries.GetForeignKeys, connection);
        cmd.Parameters.AddWithValue("@objectName", $"{schema}.{tableName}");
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var fks = new List<ForeignKeyInfo>();
        while (await reader.ReadAsync(ct))
        {
            fks.Add(new ForeignKeyInfo
            {
                Name = reader.GetString(0),
                ReferencedSchema = reader.GetString(1),
                ReferencedTable = reader.GetString(2),
                Columns = reader.GetString(3).Split(", ").ToList(),
                ReferencedColumns = reader.GetString(4).Split(", ").ToList()
            });
        }
        return fks;
    }
}
