using System.Text.Json;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.Services;

public class ConnectionStore : IConnectionStore
{
    private static readonly string StoreDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sqlexplorer");
    private static readonly string StoreFile = Path.Combine(StoreDir, "connections.json");

    public ConnectionStore()
    {
    }

    public async Task<IReadOnlyList<SavedConnection>> GetAllAsync(CancellationToken ct = default)
    {
        if (!File.Exists(StoreFile)) return [];
        var json = await File.ReadAllTextAsync(StoreFile, ct);
        return JsonSerializer.Deserialize<List<SavedConnection>>(json) ?? [];
    }

    public async Task SaveAsync(SavedConnection connection, CancellationToken ct = default)
    {
        var all = (await GetAllAsync(ct)).ToList();
        var existing = all.FindIndex(c => c.Id == connection.Id);
        if (existing >= 0)
            all[existing] = connection;
        else
            all.Add(connection);

        Directory.CreateDirectory(StoreDir);
        var json = JsonSerializer.Serialize(all, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(StoreFile, json, ct);
    }

    public async Task DeleteAsync(Guid connectionId, CancellationToken ct = default)
    {
        var all = (await GetAllAsync(ct)).ToList();
        all.RemoveAll(c => c.Id == connectionId);
        var json = JsonSerializer.Serialize(all, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(StoreFile, json, ct);
    }

    public async Task<SavedConnection?> GetByIdAsync(Guid connectionId, CancellationToken ct = default)
    {
        var all = await GetAllAsync(ct);
        return all.FirstOrDefault(c => c.Id == connectionId);
    }

    // Simple Base64 encoding for password storage — replace with DPAPI/Keychain in production
    public static string EncryptPassword(string password) =>
        Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(password));

    public static string DecryptPassword(string encrypted) =>
        System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(encrypted));
}
