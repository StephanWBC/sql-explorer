namespace SqlStudio.Core.Models;

public class DatabaseObject
{
    public string Name { get; init; } = string.Empty;
    public string Schema { get; init; } = "dbo";
    public string Database { get; init; } = string.Empty;
    public Guid ConnectionId { get; init; }
    public DatabaseObjectType ObjectType { get; init; }
    public bool IsExpandable { get; init; }
    public bool IsLoaded { get; set; }
}
