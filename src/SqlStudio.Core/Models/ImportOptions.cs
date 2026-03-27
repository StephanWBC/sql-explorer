namespace SqlStudio.Core.Models;

public class ImportOptions
{
    public bool HasHeaderRow { get; init; } = true;
    public string Delimiter { get; init; } = ",";
    public int BatchSize { get; init; } = 1000;
    public bool TruncateBeforeImport { get; init; }
}
