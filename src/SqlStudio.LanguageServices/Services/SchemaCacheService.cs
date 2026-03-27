using System.Collections.Concurrent;
using SqlStudio.Core.Interfaces;
using SqlStudio.LanguageServices.Interfaces;
using SqlStudio.LanguageServices.Models;

namespace SqlStudio.LanguageServices.Services;

public class SchemaCacheService : ISchemaCacheService
{
    private readonly IObjectExplorerService _objectExplorer;
    private readonly ConcurrentDictionary<(Guid, string), SchemaCache> _caches = new();

    public SchemaCacheService(IObjectExplorerService objectExplorer)
    {
        _objectExplorer = objectExplorer;
    }

    public async Task RefreshAsync(Guid connectionId, string database, CancellationToken ct = default)
    {
        var cache = new SchemaCache();

        var tables = await _objectExplorer.GetTablesAsync(connectionId, database, ct: ct);
        foreach (var t in tables)
        {
            if (!cache.TablesBySchema.ContainsKey(t.Schema))
                cache.TablesBySchema[t.Schema] = new List<string>();
            cache.TablesBySchema[t.Schema].Add(t.Name);

            if (!cache.Schemas.Contains(t.Schema))
                cache.Schemas.Add(t.Schema);
        }

        var views = await _objectExplorer.GetViewsAsync(connectionId, database, ct: ct);
        foreach (var v in views)
        {
            if (!cache.ViewsBySchema.ContainsKey(v.Schema))
                cache.ViewsBySchema[v.Schema] = new List<string>();
            cache.ViewsBySchema[v.Schema].Add(v.Name);
        }

        var procs = await _objectExplorer.GetStoredProceduresAsync(connectionId, database, ct: ct);
        foreach (var p in procs)
        {
            if (!cache.ProceduresBySchema.ContainsKey(p.Schema))
                cache.ProceduresBySchema[p.Schema] = new List<string>();
            cache.ProceduresBySchema[p.Schema].Add(p.Name);
        }

        var funcs = await _objectExplorer.GetFunctionsAsync(connectionId, database, ct: ct);
        foreach (var f in funcs)
        {
            if (!cache.FunctionsBySchema.ContainsKey(f.Schema))
                cache.FunctionsBySchema[f.Schema] = new List<string>();
            cache.FunctionsBySchema[f.Schema].Add(f.Name);
        }

        cache.LastRefreshed = DateTime.UtcNow;
        _caches[(connectionId, database)] = cache;
    }

    public void Invalidate(Guid connectionId, string? database = null)
    {
        if (database != null)
            _caches.TryRemove((connectionId, database), out _);
        else
        {
            var keysToRemove = _caches.Keys.Where(k => k.Item1 == connectionId).ToList();
            foreach (var key in keysToRemove)
                _caches.TryRemove(key, out _);
        }
    }

    public IReadOnlyList<string> GetTableNames(Guid connectionId, string database) =>
        GetCache(connectionId, database)?.TablesBySchema.Values.SelectMany(v => v).ToList() ?? [];

    public IReadOnlyList<string> GetViewNames(Guid connectionId, string database) =>
        GetCache(connectionId, database)?.ViewsBySchema.Values.SelectMany(v => v).ToList() ?? [];

    public IReadOnlyList<string> GetColumnNames(Guid connectionId, string database, string schema, string tableName) =>
        GetCache(connectionId, database)?.ColumnsByTable.GetValueOrDefault((schema, tableName)) ?? [];

    public IReadOnlyList<string> GetStoredProcedureNames(Guid connectionId, string database) =>
        GetCache(connectionId, database)?.ProceduresBySchema.Values.SelectMany(v => v).ToList() ?? [];

    public IReadOnlyList<string> GetFunctionNames(Guid connectionId, string database) =>
        GetCache(connectionId, database)?.FunctionsBySchema.Values.SelectMany(v => v).ToList() ?? [];

    public IReadOnlyList<string> GetSchemaNames(Guid connectionId, string database) =>
        GetCache(connectionId, database)?.Schemas ?? [];

    private SchemaCache? GetCache(Guid connectionId, string database) =>
        _caches.GetValueOrDefault((connectionId, database));
}
