using SqlStudio.Core.Models;

namespace SqlStudio.Core.Interfaces;

public interface IObjectExplorerService
{
    Task<IReadOnlyList<string>> GetDatabasesAsync(Guid connectionId, CancellationToken ct = default);
    Task<IReadOnlyList<TableInfo>> GetTablesAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default);
    Task<IReadOnlyList<ViewInfo>> GetViewsAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default);
    Task<IReadOnlyList<StoredProcedureInfo>> GetStoredProceduresAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default);
    Task<IReadOnlyList<FunctionInfo>> GetFunctionsAsync(Guid connectionId, string database, string? schema = null, CancellationToken ct = default);
    Task<IReadOnlyList<ColumnInfo>> GetColumnsAsync(Guid connectionId, string database, string schema, string tableName, CancellationToken ct = default);
    Task<IReadOnlyList<IndexInfo>> GetIndexesAsync(Guid connectionId, string database, string schema, string tableName, CancellationToken ct = default);
    Task<IReadOnlyList<ForeignKeyInfo>> GetForeignKeysAsync(Guid connectionId, string database, string schema, string tableName, CancellationToken ct = default);
}
