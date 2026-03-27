using Microsoft.Data.SqlClient;
using SqlStudio.Core.DataAccess;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class ScriptGenerationService : IScriptGenerationService
{
    private readonly IConnectionManager _connectionManager;

    public ScriptGenerationService(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
    }

    public async Task<string> GenerateCreateScriptAsync(Guid connectionId, string database, DatabaseObjectType objectType, string schema, string objectName, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);
        await connection.ChangeDatabaseAsync(database, ct);
        var fullName = $"{schema}.{objectName}";

        if (objectType == DatabaseObjectType.Table)
        {
            await using var cmd = new SqlCommand(SystemTableQueries.GetTableCreateScript, connection);
            cmd.Parameters.AddWithValue("@objectName", fullName);
            var result = await cmd.ExecuteScalarAsync(ct);
            return result?.ToString() ?? $"-- Could not generate script for {fullName}";
        }

        // For views, stored procs, functions — use OBJECT_DEFINITION
        await using var defCmd = new SqlCommand(SystemTableQueries.GetObjectDefinition, connection);
        defCmd.Parameters.AddWithValue("@objectName", fullName);
        var definition = await defCmd.ExecuteScalarAsync(ct);
        return definition?.ToString() ?? $"-- Could not generate script for {fullName}";
    }

    public async Task<string> GenerateAlterScriptAsync(Guid connectionId, string database, DatabaseObjectType objectType, string schema, string objectName, CancellationToken ct = default)
    {
        var createScript = await GenerateCreateScriptAsync(connectionId, database, objectType, schema, objectName, ct);

        if (objectType == DatabaseObjectType.Table)
            return $"-- ALTER TABLE scripts must be generated manually\n-- Current definition:\n{createScript}";

        // For procs/views/functions, replace CREATE with ALTER
        return createScript.Replace("CREATE PROCEDURE", "ALTER PROCEDURE")
                          .Replace("CREATE VIEW", "ALTER VIEW")
                          .Replace("CREATE FUNCTION", "ALTER FUNCTION")
                          .Replace("CREATE   PROCEDURE", "ALTER PROCEDURE")
                          .Replace("CREATE   FUNCTION", "ALTER FUNCTION");
    }

    public Task<string> GenerateSelectTopAsync(Guid connectionId, string database, string schema, string tableName, int topN = 1000, CancellationToken ct = default)
    {
        return Task.FromResult($"SELECT TOP {topN} *\nFROM [{schema}].[{tableName}]");
    }
}
