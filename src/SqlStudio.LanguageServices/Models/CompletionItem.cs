namespace SqlStudio.LanguageServices.Models;

public class CompletionItem
{
    public string Label { get; init; } = string.Empty;
    public string InsertText { get; init; } = string.Empty;
    public CompletionItemKind Kind { get; init; }
    public string? Description { get; init; }
}

public enum CompletionItemKind
{
    Keyword,
    Table,
    View,
    Column,
    StoredProcedure,
    Function,
    Schema,
    Database
}
