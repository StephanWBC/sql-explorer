using System.Text.Json;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class ConnectionStore : IConnectionStore
{
    private static readonly string StoreDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sqlexplorer");
    private static readonly string StoreFile = Path.Combine(StoreDir, "connections.json");

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    // ── Internal wrapper for the new JSON format ──────────────────────

    private class StoreData
    {
        public List<ConnectionGroup> Groups { get; set; } = [];
        public List<SavedConnection> Connections { get; set; } = [];
    }

    private async Task<StoreData> LoadStoreAsync(CancellationToken ct = default)
    {
        if (!File.Exists(StoreFile)) return new StoreData();

        var json = await File.ReadAllTextAsync(StoreFile, ct);
        if (string.IsNullOrWhiteSpace(json)) return new StoreData();

        // Try new format first
        try
        {
            var data = JsonSerializer.Deserialize<StoreData>(json);
            if (data?.Connections != null || data?.Groups != null)
                return data ?? new StoreData();
        }
        catch { }

        // Fallback: old flat array of connections
        try
        {
            var connections = JsonSerializer.Deserialize<List<SavedConnection>>(json);
            return new StoreData { Connections = connections ?? [] };
        }
        catch { }

        return new StoreData();
    }

    private async Task SaveStoreAsync(StoreData data, CancellationToken ct = default)
    {
        Directory.CreateDirectory(StoreDir);
        var json = JsonSerializer.Serialize(data, JsonOpts);
        await File.WriteAllTextAsync(StoreFile, json, ct);
    }

    // ── Connection CRUD ───────────────────────────────────────────────

    public async Task<IReadOnlyList<SavedConnection>> GetAllAsync(CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        return data.Connections;
    }

    public async Task SaveAsync(SavedConnection connection, CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        var idx = data.Connections.FindIndex(c => c.Id == connection.Id);
        if (idx >= 0)
            data.Connections[idx] = connection;
        else
            data.Connections.Add(connection);
        await SaveStoreAsync(data, ct);
    }

    public async Task DeleteAsync(Guid connectionId, CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        data.Connections.RemoveAll(c => c.Id == connectionId);
        await SaveStoreAsync(data, ct);
    }

    public async Task<SavedConnection?> GetByIdAsync(Guid connectionId, CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        return data.Connections.FirstOrDefault(c => c.Id == connectionId);
    }

    // ── Group CRUD ────────────────────────────────────────────────────

    public async Task<IReadOnlyList<ConnectionGroup>> GetGroupsAsync(CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        return data.Groups.OrderBy(g => g.SortOrder).ThenBy(g => g.Name).ToList();
    }

    public async Task SaveGroupAsync(ConnectionGroup group, CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        var idx = data.Groups.FindIndex(g => g.Id == group.Id);
        if (idx >= 0)
            data.Groups[idx] = group;
        else
            data.Groups.Add(group);
        await SaveStoreAsync(data, ct);
    }

    public async Task DeleteGroupAsync(Guid groupId, CancellationToken ct = default)
    {
        var data = await LoadStoreAsync(ct);
        data.Groups.RemoveAll(g => g.Id == groupId);
        // Orphan connections — set GroupId to null
        foreach (var conn in data.Connections.Where(c => c.GroupId == groupId))
            conn.GroupId = null;
        await SaveStoreAsync(data, ct);
    }

    // ── Password helpers ──────────────────────────────────────────────

    public static string EncryptPassword(string password) =>
        Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(password));

    public static string DecryptPassword(string encrypted) =>
        System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(encrypted));
}
