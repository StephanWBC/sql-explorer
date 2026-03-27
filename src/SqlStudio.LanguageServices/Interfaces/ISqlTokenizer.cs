namespace SqlStudio.LanguageServices.Interfaces;

public interface ISqlTokenizer
{
    SqlCompletionContext GetContext(string text, int offset);
    string ExtractWordBeforeCaret(string text, int offset);
}

public enum SqlCompletionContext
{
    Keyword,
    TableOrView,
    Column,
    Schema,
    Database,
    StoredProcedure,
    Function,
    None
}
