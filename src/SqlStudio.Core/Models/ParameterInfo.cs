namespace SqlStudio.Core.Models;

public class ParameterInfo
{
    public string Name { get; init; } = string.Empty;
    public string DataType { get; init; } = string.Empty;
    public int MaxLength { get; init; }
    public bool IsOutput { get; init; }
    public int OrdinalPosition { get; init; }
}
