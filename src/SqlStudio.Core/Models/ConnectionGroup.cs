namespace SqlStudio.Core.Models;

public class ConnectionGroup
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public bool IsExpanded { get; set; } = true;
}
