using SqlStudio.Core.Models;

namespace SqlStudio.Core.Interfaces;

public interface IConnectionStore
{
    Task<IReadOnlyList<SavedConnection>> GetAllAsync(CancellationToken ct = default);
    Task SaveAsync(SavedConnection connection, CancellationToken ct = default);
    Task DeleteAsync(Guid connectionId, CancellationToken ct = default);
    Task<SavedConnection?> GetByIdAsync(Guid connectionId, CancellationToken ct = default);
}
