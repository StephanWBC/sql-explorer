namespace SqlStudio.Core.Models;

public class IndexInfo
{
    public string Name { get; init; } = string.Empty;
    public string Type { get; init; } = string.Empty;
    public bool IsUnique { get; init; }
    public bool IsPrimaryKey { get; init; }
    public List<string> Columns { get; init; } = [];
}
