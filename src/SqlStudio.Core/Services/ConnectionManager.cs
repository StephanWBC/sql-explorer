using System.Collections.Concurrent;
using Microsoft.Data.SqlClient;
using SqlStudio.Core.DataAccess;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class ConnectionManager : IConnectionManager
{
    private readonly ConcurrentDictionary<Guid, (ConnectionInfo Info, SqlConnection Connection)> _connections = new();

    public IReadOnlyDictionary<Guid, ConnectionInfo> ActiveConnections =>
        _connections.ToDictionary(kv => kv.Key, kv => kv.Value.Info);

    public event EventHandler<Guid>? ConnectionOpened;
    public event EventHandler<Guid>? ConnectionClosed;
    public event EventHandler<(Guid ConnectionId, string Message)>? ConnectionError;

    public async Task<Guid> ConnectAsync(ConnectionInfo connectionInfo, CancellationToken ct = default)
    {
        var connection = await SqlConnectionFactory.CreateAsync(connectionInfo, ct);

        try
        {
            await connection.OpenAsync(ct);
        }
        catch (Exception ex)
        {
            await connection.DisposeAsync();
            ConnectionError?.Invoke(this, (connectionInfo.Id, ex.Message));
            throw;
        }

        _connections[connectionInfo.Id] = (connectionInfo, connection);
        ConnectionOpened?.Invoke(this, connectionInfo.Id);
        return connectionInfo.Id;
    }

    public async Task DisconnectAsync(Guid connectionId, CancellationToken ct = default)
    {
        if (_connections.TryRemove(connectionId, out var entry))
        {
            await entry.Connection.CloseAsync();
            await entry.Connection.DisposeAsync();
            ConnectionClosed?.Invoke(this, connectionId);
        }
    }

    public async Task<bool> TestConnectionAsync(ConnectionInfo connectionInfo, CancellationToken ct = default)
    {
        await using var connection = await SqlConnectionFactory.CreateAsync(connectionInfo, ct);
        try
        {
            await connection.OpenAsync(ct);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public Task<SqlConnection> GetConnectionAsync(Guid connectionId, CancellationToken ct = default)
    {
        if (!_connections.TryGetValue(connectionId, out var entry))
            throw new InvalidOperationException($"No active connection with id {connectionId}");

        if (entry.Connection.State != System.Data.ConnectionState.Open)
            throw new InvalidOperationException($"Connection {connectionId} is not open");

        return Task.FromResult(entry.Connection);
    }

    public async ValueTask DisposeAsync()
    {
        foreach (var (_, (_, connection)) in _connections)
        {
            await connection.CloseAsync();
            await connection.DisposeAsync();
        }
        _connections.Clear();
    }
}
