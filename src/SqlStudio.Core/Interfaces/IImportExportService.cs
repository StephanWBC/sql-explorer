using SqlStudio.Core.Models;

namespace SqlStudio.Core.Interfaces;

public interface IImportExportService
{
    Task ExportToCsvAsync(QueryResult result, string filePath, ExportOptions options, CancellationToken ct = default);
    Task<int> ImportFromCsvAsync(Guid connectionId, string database, string schema, string tableName, string csvFilePath, ImportOptions options, IProgress<int>? progress = null, CancellationToken ct = default);
}
