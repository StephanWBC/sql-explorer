using SqlStudio.LanguageServices.Models;

namespace SqlStudio.LanguageServices.Interfaces;

public interface ICompletionProvider
{
    Task<IReadOnlyList<CompletionItem>> GetCompletionsAsync(
        string documentText, int caretOffset, Guid connectionId, string currentDatabase, CancellationToken ct = default);
}
