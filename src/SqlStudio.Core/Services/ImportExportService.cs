using System.Data;
using System.Globalization;
using CsvHelper;
using CsvHelper.Configuration;
using Microsoft.Data.SqlClient;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class ImportExportService : IImportExportService
{
    private readonly IConnectionManager _connectionManager;

    public ImportExportService(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
    }

    public async Task ExportToCsvAsync(QueryResult result, string filePath, ExportOptions options, CancellationToken ct = default)
    {
        await using var writer = new StreamWriter(filePath);
        await using var csv = new CsvWriter(writer, new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            Delimiter = options.Delimiter
        });

        if (options.IncludeHeaders)
        {
            foreach (var col in result.Columns)
                csv.WriteField(col.Name);
            await csv.NextRecordAsync();
        }

        foreach (var row in result.Rows)
        {
            ct.ThrowIfCancellationRequested();
            foreach (var value in row)
                csv.WriteField(value?.ToString() ?? "");
            await csv.NextRecordAsync();
        }
    }

    public async Task<int> ImportFromCsvAsync(Guid connectionId, string database, string schema, string tableName, string csvFilePath, ImportOptions options, IProgress<int>? progress = null, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);

        using var reader = new StreamReader(csvFilePath);
        using var csv = new CsvReader(reader, new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            Delimiter = options.Delimiter,
            HasHeaderRecord = options.HasHeaderRow
        });

        if (options.TruncateBeforeImport)
        {
            await using var truncCmd = connection.CreateCommand();
            truncCmd.CommandText = $"TRUNCATE TABLE [{schema}].[{tableName}]";
            await truncCmd.ExecuteNonQueryAsync(ct);
        }

        var dt = new DataTable();
        using var dr = new CsvDataReader(csv);
        dt.Load(dr);

        using var bulk = new SqlBulkCopy(connection)
        {
            DestinationTableName = $"[{schema}].[{tableName}]",
            BatchSize = options.BatchSize,
            BulkCopyTimeout = 600
        };

        bulk.SqlRowsCopied += (_, e) => progress?.Report((int)e.RowsCopied);
        bulk.NotifyAfter = options.BatchSize;

        await bulk.WriteToServerAsync(dt, ct);
        return dt.Rows.Count;
    }
}
