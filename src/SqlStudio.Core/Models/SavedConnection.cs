namespace SqlStudio.Core.Models;

public class SavedConnection
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = "master";
    public ConnectionAuthType AuthType { get; set; }
    public string? Username { get; set; }
    public string? EncryptedPassword { get; set; }
    public string? TenantId { get; set; }
    public bool TrustServerCertificate { get; set; }
    public bool Encrypt { get; set; } = true;
    public int Port { get; set; } = 1433;
    public DateTime LastConnected { get; set; }
    public Guid? GroupId { get; set; }
    public string? EnvironmentLabel { get; set; }
}
