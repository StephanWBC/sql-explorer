namespace SqlStudio.Core.Models;

public class TableInfo
{
    public string Name { get; init; } = string.Empty;
    public string Schema { get; init; } = "dbo";
    public long RowCount { get; init; }
}
