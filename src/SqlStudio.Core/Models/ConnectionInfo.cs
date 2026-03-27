namespace SqlStudio.Core.Models;

public class ConnectionInfo
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; init; } = string.Empty;
    public string Server { get; init; } = string.Empty;
    public string Database { get; init; } = "master";
    public ConnectionAuthType AuthType { get; init; }
    public string? Username { get; init; }
    public string? Password { get; init; }
    public string? TenantId { get; init; }
    public bool TrustServerCertificate { get; init; }
    public int ConnectionTimeoutSeconds { get; init; } = 30;
    public int CommandTimeoutSeconds { get; init; } = 60;
    public bool Encrypt { get; init; } = true;
    public int Port { get; init; } = 1433;
}
