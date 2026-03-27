namespace SqlStudio.Core.Models;

public class ForeignKeyInfo
{
    public string Name { get; init; } = string.Empty;
    public string ReferencedTable { get; init; } = string.Empty;
    public string ReferencedSchema { get; init; } = "dbo";
    public List<string> Columns { get; init; } = [];
    public List<string> ReferencedColumns { get; init; } = [];
}
