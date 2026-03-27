namespace SqlStudio.LanguageServices.Interfaces;

public interface ISchemaCacheService
{
    Task RefreshAsync(Guid connectionId, string database, CancellationToken ct = default);
    void Invalidate(Guid connectionId, string? database = null);
    IReadOnlyList<string> GetTableNames(Guid connectionId, string database);
    IReadOnlyList<string> GetViewNames(Guid connectionId, string database);
    IReadOnlyList<string> GetColumnNames(Guid connectionId, string database, string schema, string tableName);
    IReadOnlyList<string> GetStoredProcedureNames(Guid connectionId, string database);
    IReadOnlyList<string> GetFunctionNames(Guid connectionId, string database);
    IReadOnlyList<string> GetSchemaNames(Guid connectionId, string database);
}
