namespace SqlStudio.Core.Models;

public class ExportOptions
{
    public bool IncludeHeaders { get; init; } = true;
    public string Delimiter { get; init; } = ",";
}
