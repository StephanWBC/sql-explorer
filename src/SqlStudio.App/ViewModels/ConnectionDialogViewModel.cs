using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public partial class ConnectionDialogViewModel : ViewModelBase
{
    private readonly IConnectionManager _connectionManager;
    private readonly IConnectionStore _connectionStore;

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

    public ObservableCollection<SavedConnection> SavedConnections { get; } = new();
    public ObservableCollection<ConnectionAuthType> AuthTypes { get; } = new(
        Enum.GetValues<ConnectionAuthType>());

    public bool IsSqlAuth => AuthType == ConnectionAuthType.SqlAuthentication;
    public bool IsEntraAuth => AuthType != ConnectionAuthType.SqlAuthentication;

    // Result
    public bool DialogResult { get; private set; }
    public ConnectionInfo? ResultConnection { get; private set; }
    public Guid? ResultConnectionId { get; private set; }

    public event EventHandler? CloseRequested;

    public ConnectionDialogViewModel(IConnectionManager connectionManager, IConnectionStore connectionStore)
    {
        _connectionManager = connectionManager;
        _connectionStore = connectionStore;
        _ = LoadSavedConnectionsAsync();
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

    private async Task LoadSavedConnectionsAsync()
    {
        var connections = await _connectionStore.GetAllAsync();
        SavedConnections.Clear();
        foreach (var conn in connections)
            SavedConnections.Add(conn);
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
                    Name = string.IsNullOrWhiteSpace(ConnectionName) ? ServerName : ConnectionName,
                    Server = ServerName,
                    Port = Port,
                    Database = DatabaseName,
                    AuthType = AuthType,
                    Username = AuthType == ConnectionAuthType.SqlAuthentication ? Username : null,
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
        Name = string.IsNullOrWhiteSpace(ConnectionName) ? ServerName : ConnectionName,
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
}
