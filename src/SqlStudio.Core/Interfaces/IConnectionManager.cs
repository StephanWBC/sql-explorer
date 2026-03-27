using Microsoft.Data.SqlClient;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Interfaces;

public interface IConnectionManager : IAsyncDisposable
{
    IReadOnlyDictionary<Guid, ConnectionInfo> ActiveConnections { get; }
    Task<Guid> ConnectAsync(ConnectionInfo connectionInfo, CancellationToken ct = default);
    Task DisconnectAsync(Guid connectionId, CancellationToken ct = default);
    Task<bool> TestConnectionAsync(ConnectionInfo connectionInfo, CancellationToken ct = default);
    Task<SqlConnection> GetConnectionAsync(Guid connectionId, CancellationToken ct = default);
    event EventHandler<Guid>? ConnectionOpened;
    event EventHandler<Guid>? ConnectionClosed;
    event EventHandler<(Guid ConnectionId, string Message)>? ConnectionError;
}
