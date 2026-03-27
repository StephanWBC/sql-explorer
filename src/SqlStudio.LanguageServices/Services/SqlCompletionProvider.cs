using SqlStudio.LanguageServices.Interfaces;
using SqlStudio.LanguageServices.Models;

namespace SqlStudio.LanguageServices.Services;

public class SqlCompletionProvider : ICompletionProvider
{
    private readonly ISqlTokenizer _tokenizer;
    private readonly ISchemaCacheService _schemaCache;

    private static readonly string[] SqlKeywords =
    [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "EXISTS",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "PROCEDURE", "FUNCTION",
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
        "ON", "AS", "DISTINCT", "TOP", "ORDER", "BY", "ASC", "DESC",
        "GROUP", "HAVING", "UNION", "ALL", "EXCEPT", "INTERSECT",
        "BETWEEN", "LIKE", "IS", "NULL", "CASE", "WHEN", "THEN", "ELSE", "END",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "TRAN",
        "EXEC", "EXECUTE", "DECLARE", "SET", "PRINT", "RETURN",
        "IF", "WHILE", "BREAK", "CONTINUE", "GOTO",
        "TRY", "CATCH", "THROW", "RAISERROR",
        "WITH", "NOLOCK", "CTE", "OVER", "PARTITION", "ROW_NUMBER", "RANK",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "ISNULL",
        "CAST", "CONVERT", "GETDATE", "GETUTCDATE", "DATEADD", "DATEDIFF",
        "LEN", "SUBSTRING", "REPLACE", "TRIM", "LTRIM", "RTRIM",
        "UPPER", "LOWER", "CHARINDEX", "STUFF", "FORMAT",
        "USE", "GO", "TRUNCATE", "MERGE", "OUTPUT", "INSERTED", "DELETED",
        "IDENTITY", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT",
        "UNIQUE", "CHECK", "DEFAULT", "CLUSTERED", "NONCLUSTERED",
        "VARCHAR", "NVARCHAR", "INT", "BIGINT", "DECIMAL", "FLOAT",
        "BIT", "DATETIME", "DATE", "TIME", "UNIQUEIDENTIFIER", "MONEY"
    ];

    public SqlCompletionProvider(ISqlTokenizer tokenizer, ISchemaCacheService schemaCache)
    {
        _tokenizer = tokenizer;
        _schemaCache = schemaCache;
    }

    public Task<IReadOnlyList<CompletionItem>> GetCompletionsAsync(
        string documentText, int caretOffset, Guid connectionId, string currentDatabase, CancellationToken ct = default)
    {
        var context = _tokenizer.GetContext(documentText, caretOffset);
        var prefix = _tokenizer.ExtractWordBeforeCaret(documentText, caretOffset);

        IReadOnlyList<CompletionItem> results = context switch
        {
            SqlCompletionContext.Keyword => GetKeywordCompletions(prefix),
            SqlCompletionContext.TableOrView => GetTableAndViewCompletions(connectionId, currentDatabase, prefix),
            SqlCompletionContext.Column => GetColumnCompletions(connectionId, currentDatabase, prefix),
            SqlCompletionContext.StoredProcedure => GetProcedureCompletions(connectionId, currentDatabase, prefix),
            SqlCompletionContext.Database => [],
            SqlCompletionContext.Schema => GetSchemaCompletions(connectionId, currentDatabase, prefix),
            _ => GetKeywordCompletions(prefix)
        };

        return Task.FromResult(results);
    }

    private IReadOnlyList<CompletionItem> GetKeywordCompletions(string prefix)
    {
        return SqlKeywords
            .Where(k => k.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .Select(k => new CompletionItem
            {
                Label = k,
                InsertText = k,
                Kind = CompletionItemKind.Keyword
            })
            .ToList();
    }

    private IReadOnlyList<CompletionItem> GetTableAndViewCompletions(Guid connectionId, string database, string prefix)
    {
        var tables = _schemaCache.GetTableNames(connectionId, database)
            .Where(t => t.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .Select(t => new CompletionItem { Label = t, InsertText = t, Kind = CompletionItemKind.Table });

        var views = _schemaCache.GetViewNames(connectionId, database)
            .Where(v => v.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .Select(v => new CompletionItem { Label = v, InsertText = v, Kind = CompletionItemKind.View });

        return tables.Concat(views).ToList();
    }

    private IReadOnlyList<CompletionItem> GetColumnCompletions(Guid connectionId, string database, string prefix)
    {
        // If prefix contains a dot, try to resolve table.column
        if (prefix.Contains('.'))
        {
            var parts = prefix.Split('.');
            var tableName = parts[0];
            var colPrefix = parts.Length > 1 ? parts[1] : "";

            // Try each schema
            foreach (var schema in _schemaCache.GetSchemaNames(connectionId, database))
            {
                var columns = _schemaCache.GetColumnNames(connectionId, database, schema, tableName);
                if (columns.Count > 0)
                {
                    return columns
                        .Where(c => c.StartsWith(colPrefix, StringComparison.OrdinalIgnoreCase))
                        .Select(c => new CompletionItem { Label = c, InsertText = c, Kind = CompletionItemKind.Column })
                        .ToList();
                }
            }
        }

        // Fall back to keyword completions mixed with table names
        return GetKeywordCompletions(prefix);
    }

    private IReadOnlyList<CompletionItem> GetProcedureCompletions(Guid connectionId, string database, string prefix)
    {
        return _schemaCache.GetStoredProcedureNames(connectionId, database)
            .Where(p => p.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .Select(p => new CompletionItem { Label = p, InsertText = p, Kind = CompletionItemKind.StoredProcedure })
            .ToList();
    }

    private IReadOnlyList<CompletionItem> GetSchemaCompletions(Guid connectionId, string database, string prefix)
    {
        return _schemaCache.GetSchemaNames(connectionId, database)
            .Where(s => s.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            .Select(s => new CompletionItem { Label = s, InsertText = s, Kind = CompletionItemKind.Schema })
            .ToList();
    }
}
