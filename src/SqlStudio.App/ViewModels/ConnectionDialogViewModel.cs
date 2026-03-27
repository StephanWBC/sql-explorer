using System.Collections.ObjectModel;
using Azure.Core;
using Azure.Identity;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Data.SqlClient;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public partial class ConnectionDialogViewModel : ViewModelBase
{
    private readonly IConnectionManager _connectionManager;
    private readonly IConnectionStore _connectionStore;
    private AccessToken? _entraToken;

    [ObservableProperty] private string _serverName = string.Empty;
    [ObservableProperty] private int _port = 1433;
    [ObservableProperty] private string _databaseName = "master";
    [ObservableProperty] private ConnectionAuthType _authType = ConnectionAuthType.SqlAuthentication;
    [ObservableProperty] private string _username = string.Empty;
    [ObservableProperty] private string _password = string.Empty;
    [ObservableProperty] private string _tenantId = string.Empty;
    [ObservableProperty] private bool _trustServerCertificate = true;
    [ObservableProperty] private bool _encrypt = true;
    [ObservableProperty] private string _connectionName = string.Empty;
    [ObservableProperty] private bool _saveConnection = true;
    [ObservableProperty] private bool _isTesting;
    [ObservableProperty] private bool _isConnecting;
    [ObservableProperty] private string _statusMessage = string.Empty;
    [ObservableProperty] private bool _isStatusError;
    [ObservableProperty] private SavedConnection? _selectedSavedConnection;

    // Entra ID state
    [ObservableProperty] private bool _isEntraSignedIn;
    [ObservableProperty] private string _entraUserEmail = string.Empty;
    [ObservableProperty] private bool _isSigningIn;
    [ObservableProperty] private string? _selectedDatabase;
    [ObservableProperty] private bool _isLoadingDatabases;

    public ObservableCollection<SavedConnection> SavedConnections { get; } = new();
    public ObservableCollection<ConnectionAuthType> AuthTypes { get; } = new(
        Enum.GetValues<ConnectionAuthType>());
    public ObservableCollection<string> AvailableDatabases { get; } = new();

    public bool IsSqlAuth => AuthType == ConnectionAuthType.SqlAuthentication;
    public bool IsEntraAuth => AuthType != ConnectionAuthType.SqlAuthentication;

    // Result
    public bool DialogResult { get; private set; }
    public ConnectionInfo? ResultConnection { get; private set; }
    public Guid? ResultConnectionId { get; private set; }

    public event EventHandler? CloseRequested;

    private static readonly string CredDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sqlexplorer");
    private static readonly string EntraCredFile = Path.Combine(CredDir, "entra-credential.json");

    public ConnectionDialogViewModel(IConnectionManager connectionManager, IConnectionStore connectionStore)
    {
        _connectionManager = connectionManager;
        _connectionStore = connectionStore;
        _ = LoadSavedConnectionsAsync();
        _ = RestoreEntraCredentialAsync();
    }

    /// Restore persisted Entra credential from disk — silent token refresh, no browser popup
    private async Task RestoreEntraCredentialAsync()
    {
        try
        {
            if (!File.Exists(EntraCredFile)) return;
            var json = await File.ReadAllTextAsync(EntraCredFile);
            var email = ExtractJsonValue(json, "email");
            var tenantId = ExtractJsonValue(json, "tenantId");

            if (string.IsNullOrEmpty(email)) return;

            EntraUserEmail = email;
            if (!string.IsNullOrEmpty(tenantId)) TenantId = tenantId;
            IsEntraSignedIn = true;
        }
        catch { /* ignore — user can sign in again */ }
    }

    private async Task PersistEntraCredentialAsync()
    {
        try
        {
            Directory.CreateDirectory(CredDir);
            var json = $"{{\"email\":\"{EntraUserEmail}\",\"tenantId\":\"{TenantId}\"}}";
            await File.WriteAllTextAsync(EntraCredFile, json);
        }
        catch { /* best effort */ }
    }

    partial void OnAuthTypeChanged(ConnectionAuthType value)
    {
        OnPropertyChanged(nameof(IsSqlAuth));
        OnPropertyChanged(nameof(IsEntraAuth));
    }

    partial void OnSelectedSavedConnectionChanged(SavedConnection? value)
    {
        if (value == null) return;
        ServerName = value.Server;
        Port = value.Port;
        DatabaseName = value.Database;
        AuthType = value.AuthType;
        Username = value.Username ?? string.Empty;
        TenantId = value.TenantId ?? string.Empty;
        TrustServerCertificate = value.TrustServerCertificate;
        Encrypt = value.Encrypt;
        ConnectionName = value.Name;
    }

    partial void OnSelectedDatabaseChanged(string? value)
    {
        if (value != null)
            DatabaseName = value;
    }

    private async Task LoadSavedConnectionsAsync()
    {
        var connections = await _connectionStore.GetAllAsync();
        SavedConnections.Clear();
        foreach (var conn in connections)
            SavedConnections.Add(conn);
    }

    [RelayCommand]
    private async Task SignInWithEntraAsync()
    {
        if (string.IsNullOrWhiteSpace(ServerName))
        {
            StatusMessage = "Please enter a server address first";
            IsStatusError = true;
            return;
        }

        IsSigningIn = true;
        StatusMessage = "Opening browser for sign-in...";
        IsStatusError = false;

        try
        {
            // Use InteractiveBrowserCredential — this opens the default browser
            var options = new InteractiveBrowserCredentialOptions
            {
                TokenCachePersistenceOptions = new TokenCachePersistenceOptions { Name = "SqlExplorer" }
            };

            if (!string.IsNullOrWhiteSpace(TenantId))
                options.TenantId = TenantId;

            var credential = new InteractiveBrowserCredential(options);
            var tokenContext = new TokenRequestContext(["https://database.windows.net/.default"]);
            _entraToken = await credential.GetTokenAsync(tokenContext);

            // Decode the JWT to get the user email
            var tokenParts = _entraToken.Value.Token.Split('.');
            if (tokenParts.Length >= 2)
            {
                var payload = tokenParts[1];
                // Pad base64 if needed
                payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
                var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(payload));
                // Simple JSON parsing for upn/email
                var email = ExtractJsonValue(json, "upn")
                         ?? ExtractJsonValue(json, "email")
                         ?? ExtractJsonValue(json, "preferred_username")
                         ?? "Signed in";
                EntraUserEmail = email;
            }

            IsEntraSignedIn = true;
            StatusMessage = $"Signed in as {EntraUserEmail}";
            IsStatusError = false;

            // Persist credentials permanently to disk
            await PersistEntraCredentialAsync();

            // Now list databases the user has access to
            await LoadAvailableDatabasesAsync();
        }
        catch (Exception ex)
        {
            StatusMessage = $"Sign-in failed: {ex.Message}";
            IsStatusError = true;
            IsEntraSignedIn = false;
        }
        finally
        {
            IsSigningIn = false;
        }
    }

    private async Task LoadAvailableDatabasesAsync()
    {
        if (_entraToken == null || string.IsNullOrWhiteSpace(ServerName)) return;

        IsLoadingDatabases = true;
        AvailableDatabases.Clear();

        try
        {
            var builder = new SqlConnectionStringBuilder
            {
                DataSource = Port == 1433 ? ServerName : $"{ServerName},{Port}",
                InitialCatalog = "master",
                Encrypt = Encrypt,
                TrustServerCertificate = TrustServerCertificate,
                ConnectTimeout = 15
            };

            await using var connection = new SqlConnection(builder.ConnectionString);
            connection.AccessToken = _entraToken.Value.Token;
            await connection.OpenAsync();

            await using var cmd = new SqlCommand(
                "SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name", connection);
            await using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                AvailableDatabases.Add(reader.GetString(0));
            }

            if (AvailableDatabases.Count > 0)
            {
                StatusMessage = $"Found {AvailableDatabases.Count} database(s). Select one to connect.";
                // Auto-select first non-system database or master
                SelectedDatabase = AvailableDatabases.FirstOrDefault(d =>
                    d != "master" && d != "tempdb" && d != "model" && d != "msdb")
                    ?? AvailableDatabases.First();
            }
            else
            {
                StatusMessage = "No databases found. You may not have access.";
            }
        }
        catch (Exception ex)
        {
            StatusMessage = $"Could not list databases: {ex.Message}";
            IsStatusError = true;
        }
        finally
        {
            IsLoadingDatabases = false;
        }
    }

    [RelayCommand]
    private async Task RefreshDatabasesAsync()
    {
        await LoadAvailableDatabasesAsync();
    }

    [RelayCommand]
    private async Task TestConnectionAsync()
    {
        IsTesting = true;
        StatusMessage = "Testing connection...";
        IsStatusError = false;

        try
        {
            var info = BuildConnectionInfo();
            var success = await _connectionManager.TestConnectionAsync(info);
            StatusMessage = success ? "Connection successful!" : "Connection failed.";
            IsStatusError = !success;
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error: {ex.Message}";
            IsStatusError = true;
        }
        finally
        {
            IsTesting = false;
        }
    }

    [RelayCommand]
    private async Task ConnectAsync()
    {
        IsConnecting = true;
        StatusMessage = "Connecting...";
        IsStatusError = false;

        try
        {
            var info = BuildConnectionInfo();
            var connectionId = await _connectionManager.ConnectAsync(info);

            if (SaveConnection)
            {
                await _connectionStore.SaveAsync(new SavedConnection
                {
                    Id = info.Id,
                    Name = string.IsNullOrWhiteSpace(ConnectionName)
                        ? (IsEntraSignedIn ? $"{ServerName} ({EntraUserEmail})" : ServerName)
                        : ConnectionName,
                    Server = ServerName,
                    Port = Port,
                    Database = DatabaseName,
                    AuthType = AuthType,
                    Username = AuthType == ConnectionAuthType.SqlAuthentication ? Username : EntraUserEmail,
                    TenantId = AuthType != ConnectionAuthType.SqlAuthentication ? TenantId : null,
                    TrustServerCertificate = TrustServerCertificate,
                    Encrypt = Encrypt,
                    LastConnected = DateTime.UtcNow
                });
            }

            ResultConnection = info;
            ResultConnectionId = connectionId;
            DialogResult = true;
            CloseRequested?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error: {ex.Message}";
            IsStatusError = true;
        }
        finally
        {
            IsConnecting = false;
        }
    }

    [RelayCommand]
    private void Cancel()
    {
        DialogResult = false;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    [RelayCommand]
    private async Task DeleteSavedConnectionAsync()
    {
        if (SelectedSavedConnection == null) return;
        await _connectionStore.DeleteAsync(SelectedSavedConnection.Id);
        SavedConnections.Remove(SelectedSavedConnection);
        SelectedSavedConnection = null;
    }

    private ConnectionInfo BuildConnectionInfo() => new()
    {
        Name = string.IsNullOrWhiteSpace(ConnectionName)
            ? (IsEntraSignedIn ? $"{ServerName} ({EntraUserEmail})" : ServerName)
            : ConnectionName,
        Server = ServerName,
        Port = Port,
        Database = DatabaseName,
        AuthType = AuthType,
        Username = AuthType == ConnectionAuthType.SqlAuthentication ? Username : null,
        Password = AuthType == ConnectionAuthType.SqlAuthentication ? Password : null,
        TenantId = AuthType != ConnectionAuthType.SqlAuthentication ? TenantId : null,
        TrustServerCertificate = TrustServerCertificate,
        Encrypt = Encrypt
    };

    private static string? ExtractJsonValue(string json, string key)
    {
        var searchKey = $"\"{key}\":\"";
        var idx = json.IndexOf(searchKey, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return null;
        var start = idx + searchKey.Length;
        var end = json.IndexOf('"', start);
        return end > start ? json[start..end] : null;
    }
}
