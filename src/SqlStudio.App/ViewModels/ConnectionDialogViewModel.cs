using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text.Json;
using Azure.Core;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Extensions.Msal;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public record AzureSubscription(string Id, string Name);

public record AzureDatabase(
    string SubscriptionId,
    string SubscriptionName,
    string ResourceGroup,
    string ServerFqdn,
    string DatabaseName)
{
    public string DisplayName => $"{DatabaseName}  —  {ServerFqdn}";
    public string ContextLabel => ResourceGroup;
}

public partial class ConnectionDialogViewModel : ViewModelBase
{
    private readonly IConnectionManager _connectionManager;
    private readonly IConnectionStore _connectionStore;
    private AccessToken? _entraToken;
    private string? _armAccessToken;
    private IPublicClientApplication? _msalApp;
    private IAccount? _msalAccount;

    private static readonly string[] SqlScopes = ["https://database.windows.net/.default"];
    private static readonly string[] ArmScopes = ["https://management.azure.com/.default"];
    private const string AzureCliClientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46";

    private static readonly string CredDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sqlexplorer");
    private static readonly string EntraCredFile = Path.Combine(CredDir, "entra-credential.json");

    [ObservableProperty] private string _serverName = string.Empty;
    [ObservableProperty] private int _port = 1433;
    [ObservableProperty] private string _databaseName = "master";
    [ObservableProperty] private ConnectionAuthType _authType = ConnectionAuthType.EntraIdInteractive;
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
    [ObservableProperty] private AzureDatabase? _selectedDatabase;
    [ObservableProperty] private bool _isLoadingDatabases;
    [ObservableProperty] private bool _hasSubscriptions;
    [ObservableProperty] private AzureSubscription? _selectedSubscription;

    // Connection group + environment
    [ObservableProperty] private ConnectionGroup? _selectedGroup;
    [ObservableProperty] private string _environmentLabel = string.Empty;

    private readonly List<AzureDatabase> _allDatabases = new();

    public ObservableCollection<SavedConnection> SavedConnections { get; } = new();
    public ObservableCollection<AzureDatabase> AvailableDatabases { get; } = new();
    public ObservableCollection<AzureSubscription> AvailableSubscriptions { get; } = new();
    public ObservableCollection<ConnectionGroup> AvailableGroups { get; } = new();
    public ObservableCollection<string> EnvironmentPresets { get; } = new(EnvironmentType.Presets);
    public ObservableCollection<string> AuthTypeNames { get; } = new()
    {
        "SQL Authentication",
        "Entra ID Interactive",
        "Entra ID Default"
    };

    public string AuthTypeName
    {
        get => AuthType switch
        {
            ConnectionAuthType.EntraIdInteractive => "Entra ID Interactive",
            ConnectionAuthType.EntraIdDefault => "Entra ID Default",
            _ => "SQL Authentication"
        };
        set
        {
            AuthType = value switch
            {
                "Entra ID Interactive" => ConnectionAuthType.EntraIdInteractive,
                "Entra ID Default" => ConnectionAuthType.EntraIdDefault,
                _ => ConnectionAuthType.SqlAuthentication
            };
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsSqlAuth));
            OnPropertyChanged(nameof(IsEntraAuth));
        }
    }

    public bool IsSqlAuth => AuthType == ConnectionAuthType.SqlAuthentication;
    public bool IsEntraAuth => AuthType != ConnectionAuthType.SqlAuthentication;
    public bool DialogResult { get; private set; }
    public ConnectionInfo? ResultConnection { get; private set; }
    public Guid? ResultConnectionId { get; private set; }
    public SavedConnection? ResultSavedConnection { get; private set; }
    public event EventHandler? CloseRequested;

    public ConnectionDialogViewModel(IConnectionManager connectionManager, IConnectionStore connectionStore)
    {
        _connectionManager = connectionManager;
        _connectionStore = connectionStore;
        _ = LoadSavedConnectionsAsync();
        _ = LoadGroupsAsync();
        _ = RestoreEntraCredentialAsync();
    }

    private async Task LoadGroupsAsync()
    {
        var groups = await _connectionStore.GetGroupsAsync();
        AvailableGroups.Clear();
        foreach (var g in groups)
            AvailableGroups.Add(g);
    }

    [RelayCommand]
    private async Task CreateGroupAsync()
    {
        var group = new ConnectionGroup { Name = $"New Group {AvailableGroups.Count + 1}" };
        await _connectionStore.SaveGroupAsync(group);
        AvailableGroups.Add(group);
        SelectedGroup = group;
    }

    [RelayCommand]
    private async Task DeleteGroupAsync()
    {
        if (SelectedGroup == null) return;
        await _connectionStore.DeleteGroupAsync(SelectedGroup.Id);
        AvailableGroups.Remove(SelectedGroup);
        SelectedGroup = null;
    }

    // ── MSAL with persistent token cache ──────────────────────────────

    private async Task<IPublicClientApplication> GetOrCreateMsalAppAsync()
    {
        if (_msalApp != null) return _msalApp;

        var authority = string.IsNullOrWhiteSpace(TenantId)
            ? "https://login.microsoftonline.com/organizations"
            : $"https://login.microsoftonline.com/{TenantId}";

        _msalApp = PublicClientApplicationBuilder
            .Create(AzureCliClientId)
            .WithAuthority(authority)
            .WithDefaultRedirectUri()
            .Build();

        // Persistent token cache — survives app restarts
        Directory.CreateDirectory(CredDir);
        var storageProps = new StorageCreationPropertiesBuilder("msal_cache.bin", CredDir)
            .WithUnprotectedFile()
            .Build();

        var cacheHelper = await MsalCacheHelper.CreateAsync(storageProps);
        cacheHelper.RegisterCache(_msalApp.UserTokenCache);

        return _msalApp;
    }

    // ── Restore / persist ─────────────────────────────────────────────

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

            // Try silent refresh from persistent MSAL cache
            var app = await GetOrCreateMsalAppAsync();
            var accounts = await app.GetAccountsAsync();
            var account = accounts.FirstOrDefault();
            if (account == null) return;

            _msalAccount = account;
            var armResult = await app.AcquireTokenSilent(ArmScopes, account).ExecuteAsync();
            _armAccessToken = armResult.AccessToken;

            try
            {
                var sqlResult = await app.AcquireTokenSilent(SqlScopes, account).ExecuteAsync();
                _entraToken = new AccessToken(sqlResult.AccessToken, sqlResult.ExpiresOn);
            }
            catch { }

            IsEntraSignedIn = true;
            await DiscoverSubscriptionsAsync();
        }
        catch
        {
            // Token cache expired — user needs to sign in again
            IsEntraSignedIn = false;
        }
    }

    private async Task PersistEntraCredentialAsync()
    {
        try
        {
            Directory.CreateDirectory(CredDir);
            var json = $"{{\"email\":\"{EntraUserEmail}\",\"tenantId\":\"{TenantId}\"}}";
            await File.WriteAllTextAsync(EntraCredFile, json);
        }
        catch { }
    }

    // ── Auth type / selection changes ─────────────────────────────────

    partial void OnAuthTypeChanged(ConnectionAuthType value)
    {
        OnPropertyChanged(nameof(IsSqlAuth));
        OnPropertyChanged(nameof(IsEntraAuth));
        OnPropertyChanged(nameof(AuthTypeName));
    }

    partial void OnSelectedDatabaseChanged(AzureDatabase? value)
    {
        if (value == null) return;
        ServerName = value.ServerFqdn;
        DatabaseName = value.DatabaseName;
    }

    partial void OnSelectedSubscriptionChanged(AzureSubscription? value)
    {
        // Drill down: show only databases from the selected subscription
        AvailableDatabases.Clear();
        if (value == null) return;

        IsLoadingDatabases = true;
        StatusMessage = $"Loading databases for {value.Name}...";
        IsStatusError = false;

        _ = LoadDatabasesForSubscriptionAsync(value);
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

    private async Task LoadSavedConnectionsAsync()
    {
        var connections = await _connectionStore.GetAllAsync();
        SavedConnections.Clear();
        foreach (var conn in connections)
            SavedConnections.Add(conn);
    }

    // ── Sign in ───────────────────────────────────────────────────────

    [RelayCommand]
    private async Task SignInWithEntraAsync()
    {
        IsSigningIn = true;
        StatusMessage = "Opening browser for sign-in...";
        IsStatusError = false;

        try
        {
            var app = await GetOrCreateMsalAppAsync();
            AuthenticationResult armResult;

            try
            {
                var accounts = await app.GetAccountsAsync();
                armResult = await app.AcquireTokenSilent(ArmScopes, accounts.FirstOrDefault())
                    .ExecuteAsync();
            }
            catch (MsalUiRequiredException)
            {
                armResult = await app.AcquireTokenInteractive(ArmScopes)
                    .WithSystemWebViewOptions(new SystemWebViewOptions
                    {
                        OpenBrowserAsync = OpenBrowserInIncognito
                    })
                    .ExecuteAsync();
            }

            _msalAccount = armResult.Account;
            _armAccessToken = armResult.AccessToken;
            EntraUserEmail = armResult.Account?.Username ?? "Signed in";

            // Get SQL token silently (same session)
            StatusMessage = "Acquiring database credentials...";
            try
            {
                var sqlResult = await app.AcquireTokenSilent(SqlScopes, _msalAccount).ExecuteAsync();
                _entraToken = new AccessToken(sqlResult.AccessToken, sqlResult.ExpiresOn);
            }
            catch { }

            IsEntraSignedIn = true;
            IsStatusError = false;
            await PersistEntraCredentialAsync();
            await DiscoverSubscriptionsAsync();
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

    // ── Azure discovery (2-step: subscriptions → databases) ───────────

    private async Task DiscoverSubscriptionsAsync()
    {
        StatusMessage = "Loading subscriptions...";
        IsStatusError = false;
        AvailableSubscriptions.Clear();
        _allDatabases.Clear();
        AvailableDatabases.Clear();
        HasSubscriptions = false;

        try
        {
            if (string.IsNullOrEmpty(_armAccessToken))
            {
                StatusMessage = "Sign in to discover your subscriptions.";
                return;
            }

            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", _armAccessToken);

            var subsJson = await http.GetStringAsync(
                "https://management.azure.com/subscriptions?api-version=2022-12-01");

            using var doc = JsonDocument.Parse(subsJson);
            if (doc.RootElement.TryGetProperty("value", out var arr))
            {
                foreach (var sub in arr.EnumerateArray())
                {
                    var id = sub.TryGetProperty("subscriptionId", out var idEl) ? idEl.GetString() ?? "" : "";
                    var name = sub.TryGetProperty("displayName", out var nameEl) ? nameEl.GetString() ?? id : id;
                    if (!string.IsNullOrEmpty(id))
                        AvailableSubscriptions.Add(new AzureSubscription(id, name));
                }
            }

            HasSubscriptions = AvailableSubscriptions.Count > 0;

            if (HasSubscriptions)
            {
                StatusMessage = $"Found {AvailableSubscriptions.Count} subscription(s). Select one to see databases.";
                // Auto-select first subscription
                SelectedSubscription = AvailableSubscriptions.First();
            }
            else
            {
                StatusMessage = "No Azure subscriptions found for this account.";
            }
        }
        catch (Exception ex)
        {
            StatusMessage = $"Could not load subscriptions: {ex.Message}";
            IsStatusError = true;
        }
    }

    private async Task LoadDatabasesForSubscriptionAsync(AzureSubscription subscription)
    {
        AvailableDatabases.Clear();

        try
        {
            if (string.IsNullOrEmpty(_armAccessToken)) return;

            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", _armAccessToken);

            // List SQL servers in this subscription
            var serversJson = await http.GetStringAsync(
                $"https://management.azure.com/subscriptions/{subscription.Id}/providers/Microsoft.Sql/servers?api-version=2021-11-01");

            using var serversDoc = JsonDocument.Parse(serversJson);
            if (!serversDoc.RootElement.TryGetProperty("value", out var serversArr))
            {
                StatusMessage = "No SQL servers found in this subscription.";
                IsLoadingDatabases = false;
                return;
            }

            foreach (var server in serversArr.EnumerateArray())
            {
                var serverId = server.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? "" : "";
                var fqdn = "";
                if (server.TryGetProperty("properties", out var props) &&
                    props.TryGetProperty("fullyQualifiedDomainName", out var fqdnEl))
                    fqdn = fqdnEl.GetString() ?? "";

                if (string.IsNullOrEmpty(fqdn) || string.IsNullOrEmpty(serverId)) continue;

                var parts = serverId.Split('/', StringSplitOptions.RemoveEmptyEntries);
                var rgIdx = Array.FindIndex(parts, p => p.Equals("resourceGroups", StringComparison.OrdinalIgnoreCase));
                var srvIdx = Array.FindIndex(parts, p => p.Equals("servers", StringComparison.OrdinalIgnoreCase));
                if (rgIdx < 0 || srvIdx < 0) continue;
                var rg = parts[rgIdx + 1];
                var srvName = parts[srvIdx + 1];

                StatusMessage = $"Scanning {fqdn}...";

                try
                {
                    var dbsJson = await http.GetStringAsync(
                        $"https://management.azure.com/subscriptions/{subscription.Id}/resourceGroups/{rg}/providers/Microsoft.Sql/servers/{srvName}/databases?api-version=2021-11-01");
                    using var dbsDoc = JsonDocument.Parse(dbsJson);
                    if (!dbsDoc.RootElement.TryGetProperty("value", out var dbsArr)) continue;

                    foreach (var db in dbsArr.EnumerateArray())
                    {
                        var dbName = db.TryGetProperty("name", out var nameEl) ? nameEl.GetString() ?? "" : "";
                        if (string.IsNullOrEmpty(dbName) || dbName == "master") continue;
                        AvailableDatabases.Add(new AzureDatabase(subscription.Id, subscription.Name, rg, fqdn, dbName));
                    }
                }
                catch { }
            }

            if (AvailableDatabases.Count > 0)
            {
                StatusMessage = $"Found {AvailableDatabases.Count} database(s) in {subscription.Name}.";
                SelectedDatabase = AvailableDatabases.FirstOrDefault();
            }
            else
            {
                StatusMessage = $"No SQL databases found in {subscription.Name}.";
            }
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error: {ex.Message}";
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
        if (SelectedSubscription != null)
        {
            IsLoadingDatabases = true;
            await LoadDatabasesForSubscriptionAsync(SelectedSubscription);
        }
        else
        {
            await DiscoverSubscriptionsAsync();
        }
    }

    // ── Incognito browser launcher ────────────────────────────────────

    private static Task OpenBrowserInIncognito(Uri uri)
    {
        var url = uri.AbsoluteUri;

        if (OperatingSystem.IsMacOS())
        {
            // Detect default browser on macOS via LaunchServices
            var defaultBrowser = DetectDefaultBrowserMac();

            // Map browser bundle ID / name to private browsing flags
            var privateFlag = defaultBrowser?.ToLowerInvariant() switch
            {
                var b when b != null && b.Contains("firefox") => "--private-window",
                var b when b != null && b.Contains("safari") => "", // Safari doesn't support CLI private mode
                _ => "--incognito" // Chrome, Brave, Arc, Edge, Chromium all use --incognito
            };

            if (!string.IsNullOrEmpty(privateFlag))
            {
                // Known browsers that support private mode via CLI
                (string app, string flag)[] browsers =
                [
                    ("Google Chrome", "--incognito"),
                    ("Brave Browser", "--incognito"),
                    ("Microsoft Edge", "--inprivate"),
                    ("Arc", "--incognito"),
                    ("Chromium", "--incognito"),
                    ("Firefox", "--private-window"),
                    ("Vivaldi", "--incognito"),
                    ("Opera", "--private"),
                ];

                foreach (var (app, flag) in browsers)
                {
                    if (!Directory.Exists($"/Applications/{app}.app")) continue;
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "open",
                        Arguments = $"-na \"{app}\" --args {flag} --new-window \"{url}\"",
                        UseShellExecute = false
                    });
                    return Task.CompletedTask;
                }
            }

            // Fallback: open in default browser (no private mode guarantee)
            Process.Start(new ProcessStartInfo { FileName = "open", Arguments = $"\"{url}\"", UseShellExecute = false });
        }
        else if (OperatingSystem.IsWindows())
        {
            // Try common Windows browsers with private flags
            (string path, string flag)[] winBrowsers =
            [
                (Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Google\Chrome\Application\chrome.exe"), "--incognito"),
                (@"C:\Program Files\Google\Chrome\Application\chrome.exe", "--incognito"),
                (@"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", "--inprivate"),
                (@"C:\Program Files\Microsoft\Edge\Application\msedge.exe", "--inprivate"),
                (@"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe", "--incognito"),
                (@"C:\Program Files\Mozilla Firefox\firefox.exe", "--private-window"),
            ];

            foreach (var (path, flag) in winBrowsers)
            {
                if (!File.Exists(path)) continue;
                Process.Start(new ProcessStartInfo { FileName = path, Arguments = $"{flag} --new-window \"{url}\"", UseShellExecute = false });
                return Task.CompletedTask;
            }

            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }

        return Task.CompletedTask;
    }

    private static string? DetectDefaultBrowserMac()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "defaults",
                Arguments = "read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            var proc = Process.Start(psi);
            var output = proc?.StandardOutput.ReadToEnd() ?? "";
            proc?.WaitForExit();

            // Look for the http handler
            if (output.Contains("com.google.chrome", StringComparison.OrdinalIgnoreCase)) return "Google Chrome";
            if (output.Contains("com.brave.browser", StringComparison.OrdinalIgnoreCase)) return "Brave Browser";
            if (output.Contains("com.microsoft.edgemac", StringComparison.OrdinalIgnoreCase)) return "Microsoft Edge";
            if (output.Contains("org.mozilla.firefox", StringComparison.OrdinalIgnoreCase)) return "Firefox";
            if (output.Contains("company.thebrowser.browser", StringComparison.OrdinalIgnoreCase)) return "Arc";
            if (output.Contains("com.apple.safari", StringComparison.OrdinalIgnoreCase)) return "Safari";
            if (output.Contains("com.vivaldi.vivaldi", StringComparison.OrdinalIgnoreCase)) return "Vivaldi";
        }
        catch { }

        return null;
    }

    private static string? ExtractEmailFromToken(string token)
    {
        var parts = token.Split('.');
        if (parts.Length < 2) return null;
        var payload = parts[1].PadRight(parts[1].Length + (4 - parts[1].Length % 4) % 4, '=');
        try
        {
            var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(payload));
            return ExtractJsonValue(json, "upn")
                ?? ExtractJsonValue(json, "email")
                ?? ExtractJsonValue(json, "preferred_username");
        }
        catch { return null; }
    }

    // ── Connect / Test / Cancel ───────────────────────────────────────

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
        finally { IsTesting = false; }
    }

    [RelayCommand]
    private async Task ConnectAsync()
    {
        IsConnecting = true;
        StatusMessage = "Connecting...";
        IsStatusError = false;
        try
        {
            // Ensure we have a SQL token
            if (_entraToken == null && _msalAccount != null)
            {
                var app = await GetOrCreateMsalAppAsync();
                var sqlResult = await app.AcquireTokenSilent(SqlScopes, _msalAccount).ExecuteAsync();
                _entraToken = new AccessToken(sqlResult.AccessToken, sqlResult.ExpiresOn);
            }

            var info = BuildConnectionInfo();
            var connectionId = await _connectionManager.ConnectAsync(info);

            var savedConn = new SavedConnection
            {
                Id = info.Id,
                Name = string.IsNullOrWhiteSpace(ConnectionName)
                    ? (IsEntraSignedIn ? $"{DatabaseName} ({EntraUserEmail})" : ServerName)
                    : ConnectionName,
                Server = ServerName,
                Port = Port,
                Database = DatabaseName,
                AuthType = AuthType,
                Username = AuthType == ConnectionAuthType.SqlAuthentication ? Username : EntraUserEmail,
                TenantId = AuthType != ConnectionAuthType.SqlAuthentication ? TenantId : null,
                TrustServerCertificate = TrustServerCertificate,
                Encrypt = Encrypt,
                LastConnected = DateTime.UtcNow,
                GroupId = SelectedGroup?.Id,
                EnvironmentLabel = string.IsNullOrWhiteSpace(EnvironmentLabel) ? null : EnvironmentLabel.Trim()
            };

            if (SaveConnection)
                await _connectionStore.SaveAsync(savedConn);

            ResultConnection = info;
            ResultConnectionId = connectionId;
            ResultSavedConnection = savedConn;
            DialogResult = true;
            CloseRequested?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error: {ex.Message}";
            IsStatusError = true;
        }
        finally { IsConnecting = false; }
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
            ? (IsEntraSignedIn ? $"{DatabaseName} ({EntraUserEmail})" : ServerName)
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
