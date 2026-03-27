using SqlStudio.Core.Models;

namespace SqlStudio.Core.Interfaces;

public interface IScriptGenerationService
{
    Task<string> GenerateCreateScriptAsync(Guid connectionId, string database, DatabaseObjectType objectType, string schema, string objectName, CancellationToken ct = default);
    Task<string> GenerateAlterScriptAsync(Guid connectionId, string database, DatabaseObjectType objectType, string schema, string objectName, CancellationToken ct = default);
    Task<string> GenerateSelectTopAsync(Guid connectionId, string database, string schema, string tableName, int topN = 1000, CancellationToken ct = default);
}
