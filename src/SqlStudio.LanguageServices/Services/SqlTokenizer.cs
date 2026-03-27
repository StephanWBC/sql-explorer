using SqlStudio.LanguageServices.Interfaces;

namespace SqlStudio.LanguageServices.Services;

public class SqlTokenizer : ISqlTokenizer
{
    private static readonly HashSet<string> TableContextKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "FROM", "JOIN", "INNER", "LEFT", "RIGHT", "CROSS", "FULL",
        "INTO", "UPDATE", "TABLE", "TRUNCATE", "DROP"
    };

    private static readonly HashSet<string> ColumnContextKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "SELECT", "WHERE", "AND", "OR", "ON", "SET", "BY", "HAVING", "BETWEEN"
    };

    private static readonly HashSet<string> ProcContextKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        "EXEC", "EXECUTE"
    };

    public SqlCompletionContext GetContext(string text, int offset)
    {
        if (string.IsNullOrEmpty(text) || offset <= 0)
            return SqlCompletionContext.Keyword;

        // Check if we're after a dot (schema.table or table.column context)
        var beforeCaret = text[..offset].TrimEnd();
        if (beforeCaret.EndsWith('.'))
            return SqlCompletionContext.Column;

        var previousKeyword = GetPreviousKeyword(text, offset);

        if (previousKeyword != null)
        {
            if (TableContextKeywords.Contains(previousKeyword))
                return SqlCompletionContext.TableOrView;
            if (ColumnContextKeywords.Contains(previousKeyword))
                return SqlCompletionContext.Column;
            if (ProcContextKeywords.Contains(previousKeyword))
                return SqlCompletionContext.StoredProcedure;
            if (previousKeyword.Equals("USE", StringComparison.OrdinalIgnoreCase))
                return SqlCompletionContext.Database;
        }

        return SqlCompletionContext.Keyword;
    }

    public string ExtractWordBeforeCaret(string text, int offset)
    {
        if (string.IsNullOrEmpty(text) || offset <= 0) return string.Empty;

        var end = Math.Min(offset, text.Length);
        var start = end - 1;

        while (start >= 0 && (char.IsLetterOrDigit(text[start]) || text[start] == '_' || text[start] == '.'))
            start--;

        return text[(start + 1)..end];
    }

    private static string? GetPreviousKeyword(string text, int offset)
    {
        var pos = offset - 1;

        // Skip current word
        while (pos >= 0 && (char.IsLetterOrDigit(text[pos]) || text[pos] == '_'))
            pos--;

        // Skip whitespace
        while (pos >= 0 && char.IsWhiteSpace(text[pos]))
            pos--;

        if (pos < 0) return null;

        // Read previous word
        var end = pos + 1;
        while (pos >= 0 && (char.IsLetterOrDigit(text[pos]) || text[pos] == '_'))
            pos--;

        return text[(pos + 1)..end];
    }
}
