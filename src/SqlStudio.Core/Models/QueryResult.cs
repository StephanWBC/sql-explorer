namespace SqlStudio.Core.Models;

public class QueryResult
{
    public List<QueryResultColumn> Columns { get; init; } = [];
    public List<object?[]> Rows { get; init; } = [];
    public QueryExecutionStats Stats { get; init; } = new();
    public bool HasMoreRows { get; init; }
    public string? ErrorMessage { get; init; }
    public bool IsError => ErrorMessage is not null;
}

public class QueryResultColumn
{
    public string Name { get; init; } = string.Empty;
    public string DataType { get; init; } = string.Empty;
    public int Ordinal { get; init; }
}

public class QueryExecutionStats
{
    public int RowsAffected { get; init; }
    public long ElapsedMilliseconds { get; init; }
    public List<string> Messages { get; init; } = [];
}
