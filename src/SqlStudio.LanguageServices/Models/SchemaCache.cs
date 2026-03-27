namespace SqlStudio.LanguageServices.Models;

public class SchemaCache
{
    public Dictionary<string, List<string>> TablesBySchema { get; } = new();
    public Dictionary<string, List<string>> ViewsBySchema { get; } = new();
    public Dictionary<(string Schema, string Table), List<string>> ColumnsByTable { get; } = new();
    public Dictionary<string, List<string>> ProceduresBySchema { get; } = new();
    public Dictionary<string, List<string>> FunctionsBySchema { get; } = new();
    public List<string> Schemas { get; } = new();
    public DateTime LastRefreshed { get; set; }
}
