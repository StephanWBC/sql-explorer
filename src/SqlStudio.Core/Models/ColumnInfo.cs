namespace SqlStudio.Core.Models;

public class ColumnInfo
{
    public string Name { get; init; } = string.Empty;
    public string DataType { get; init; } = string.Empty;
    public int MaxLength { get; init; }
    public int Precision { get; init; }
    public int Scale { get; init; }
    public bool IsNullable { get; init; }
    public bool IsIdentity { get; init; }
    public bool IsPrimaryKey { get; init; }
    public int OrdinalPosition { get; init; }
    public string? DefaultValue { get; init; }
}
