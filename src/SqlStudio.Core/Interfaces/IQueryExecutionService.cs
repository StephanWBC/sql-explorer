using SqlStudio.Core.Models;

namespace SqlStudio.Core.Interfaces;

public interface IQueryExecutionService
{
    Task<QueryResult> ExecuteQueryAsync(Guid connectionId, string sql, string databaseName, CancellationToken ct = default);
    Task<int> ExecuteNonQueryAsync(Guid connectionId, string sql, string databaseName, CancellationToken ct = default);
    void CancelQuery(Guid executionId);
    event EventHandler<QueryExecutionStats>? ExecutionCompleted;
    event EventHandler<(Guid ExecutionId, string Message)>? ExecutionMessage;
}
