using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;
using SqlStudio.Core.Models;

namespace SqlStudio.Core.DataAccess;

public static class SqlConnectionFactory
{
    public static async Task<SqlConnection> CreateAsync(ConnectionInfo info, CancellationToken ct = default)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = info.Port == 1433 ? info.Server : $"{info.Server},{info.Port}",
            InitialCatalog = info.Database,
            Encrypt = info.Encrypt,
            TrustServerCertificate = info.TrustServerCertificate,
            ConnectTimeout = info.ConnectionTimeoutSeconds,
            CommandTimeout = info.CommandTimeoutSeconds,
            ApplicationName = "SQL Explorer",
            Pooling = true,
            MinPoolSize = 1,
            MaxPoolSize = 10
        };

        SqlConnection connection;

        switch (info.AuthType)
        {
            case ConnectionAuthType.SqlAuthentication:
                builder.UserID = info.Username;
                builder.Password = info.Password;
                connection = new SqlConnection(builder.ConnectionString);
                break;

            case ConnectionAuthType.EntraIdInteractive:
                builder.Authentication = SqlAuthenticationMethod.ActiveDirectoryInteractive;
                connection = new SqlConnection(builder.ConnectionString);
                break;

            case ConnectionAuthType.EntraIdDefault:
                connection = new SqlConnection(builder.ConnectionString);
                var credential = new DefaultAzureCredential(
                    new DefaultAzureCredentialOptions { TenantId = info.TenantId });
                var token = await credential.GetTokenAsync(
                    new TokenRequestContext(["https://database.windows.net/.default"]), ct);
                connection.AccessToken = token.Token;
                break;

            default:
                throw new ArgumentOutOfRangeException(nameof(info.AuthType));
        }

        return connection;
    }
}
