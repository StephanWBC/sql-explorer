using System.Collections.Concurrent;
using System.Data;
using System.Diagnostics;
using Microsoft.Data.SqlClient;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class QueryExecutionService : IQueryExecutionService
{
    private readonly IConnectionManager _connectionManager;
    private readonly ConcurrentDictionary<Guid, SqlCommand> _runningCommands = new();

    public event EventHandler<QueryExecutionStats>? ExecutionCompleted;
    public event EventHandler<(Guid ExecutionId, string Message)>? ExecutionMessage;

    public QueryExecutionService(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
    }

    public async Task<QueryResult> ExecuteQueryAsync(Guid connectionId, string sql, string databaseName, CancellationToken ct = default)
    {
        var executionId = Guid.NewGuid();
        var sw = Stopwatch.StartNew();
        var messages = new List<string>();

        try
        {
            var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);

            if (connection.Database != databaseName)
                await connection.ChangeDatabaseAsync(databaseName, ct);

            await using var command = connection.CreateCommand();
            command.CommandText = sql;
            command.CommandTimeout = 60;

            _runningCommands[executionId] = command;

            connection.InfoMessage += (_, e) =>
            {
                messages.Add(e.Message);
                ExecutionMessage?.Invoke(this, (executionId, e.Message));
            };

            await using var reader = await command.ExecuteReaderAsync(ct);

            var columns = new List<QueryResultColumn>();
            var schema = await reader.GetColumnSchemaAsync(ct);
            for (var i = 0; i < schema.Count; i++)
            {
                columns.Add(new QueryResultColumn
                {
                    Name = schema[i].ColumnName,
                    DataType = schema[i].DataTypeName ?? "unknown",
                    Ordinal = i
                });
            }

            var rows = new List<object?[]>();
            const int maxRows = 50000;
            var hasMore = false;

            while (await reader.ReadAsync(ct))
            {
                if (rows.Count >= maxRows)
                {
                    hasMore = true;
                    break;
                }

                var row = new object?[columns.Count];
                for (var i = 0; i < columns.Count; i++)
                {
                    row[i] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                }
                rows.Add(row);
            }

            sw.Stop();
            var stats = new QueryExecutionStats
            {
                RowsAffected = rows.Count,
                ElapsedMilliseconds = sw.ElapsedMilliseconds,
                Messages = messages
            };

            ExecutionCompleted?.Invoke(this, stats);

            return new QueryResult
            {
                Columns = columns,
                Rows = rows,
                Stats = stats,
                HasMoreRows = hasMore
            };
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            sw.Stop();
            return new QueryResult
            {
                ErrorMessage = ex.Message,
                Stats = new QueryExecutionStats
                {
                    ElapsedMilliseconds = sw.ElapsedMilliseconds,
                    Messages = messages
                }
            };
        }
        finally
        {
            _runningCommands.TryRemove(executionId, out _);
        }
    }

    public async Task<int> ExecuteNonQueryAsync(Guid connectionId, string sql, string databaseName, CancellationToken ct = default)
    {
        var connection = await _connectionManager.GetConnectionAsync(connectionId, ct);

        if (connection.Database != databaseName)
            await connection.ChangeDatabaseAsync(databaseName, ct);

        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = 60;

        return await command.ExecuteNonQueryAsync(ct);
    }

    public void CancelQuery(Guid executionId)
    {
        if (_runningCommands.TryGetValue(executionId, out var command))
        {
            try { command.Cancel(); } catch { /* swallow cancel exceptions */ }
        }
    }
}
