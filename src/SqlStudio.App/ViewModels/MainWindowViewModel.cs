using System.Collections.ObjectModel;
using Avalonia;
using Avalonia.Styling;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public partial class MainWindowViewModel : ViewModelBase
{
    private readonly IConnectionManager _connectionManager;
    private readonly IObjectExplorerService _objectExplorerService;
    private readonly IQueryExecutionService _queryExecutionService;
    private readonly IScriptGenerationService _scriptService;
    private readonly IImportExportService _importExportService;
    private readonly ISettingsService _settingsService;

    [ObservableProperty] private string _title = "SQL Explorer";
    [ObservableProperty] private QueryTabViewModel? _selectedTab;
    [ObservableProperty] private string _statusBarText = "Ready";
    [ObservableProperty] private string _connectionStatus = "Disconnected";
    [ObservableProperty] private string _currentDatabase = "";
    [ObservableProperty] private bool _isDarkTheme = true;
    [ObservableProperty] private bool _isConnected;
    [ObservableProperty] private Guid _activeConnectionId;
    [ObservableProperty] private string _activeConnectionName = string.Empty;

    public ObservableCollection<ObjectExplorerNodeViewModel> ObjectExplorerNodes { get; } = new();
    public ObservableCollection<QueryTabViewModel> QueryTabs { get; } = new();

    // Event for requesting connection dialog from view
    public event EventHandler? ConnectRequested;
    public event Func<Task<(bool Result, string FilePath)>>? SaveFileRequested;
    public event Func<Task<(bool Result, string FilePath)>>? OpenFileRequested;

    public MainWindowViewModel(
        IConnectionManager connectionManager,
        IObjectExplorerService objectExplorerService,
        IQueryExecutionService queryExecutionService,
        IScriptGenerationService scriptService,
        IImportExportService importExportService,
        ISettingsService settingsService)
    {
        _connectionManager = connectionManager;
        _objectExplorerService = objectExplorerService;
        _queryExecutionService = queryExecutionService;
        _scriptService = scriptService;
        _importExportService = importExportService;
        _settingsService = settingsService;

        _connectionManager.ConnectionOpened += OnConnectionOpened;
        _connectionManager.ConnectionClosed += OnConnectionClosed;
    }

    [RelayCommand]
    private void Connect()
    {
        ConnectRequested?.Invoke(this, EventArgs.Empty);
    }

    public void OnConnected(Guid connectionId, ConnectionInfo connectionInfo)
    {
        ActiveConnectionId = connectionId;
        ActiveConnectionName = connectionInfo.Name;
        IsConnected = true;
        ConnectionStatus = $"Connected: {connectionInfo.Server}";
        CurrentDatabase = connectionInfo.Database;
        StatusBarText = $"Connected to {connectionInfo.Server}";

        // Add server node to Object Explorer
        var serverNode = new ObjectExplorerNodeViewModel(
            new DatabaseObject
            {
                Name = connectionInfo.Server,
                ConnectionId = connectionId,
                ObjectType = DatabaseObjectType.Server,
                IsExpandable = true
            }, _objectExplorerService, _scriptService);

        ObjectExplorerNodes.Add(serverNode);
    }

    [RelayCommand]
    private async Task DisconnectAsync()
    {
        if (ActiveConnectionId == Guid.Empty) return;

        await _connectionManager.DisconnectAsync(ActiveConnectionId);
        ObjectExplorerNodes.Clear();
        IsConnected = false;
        ConnectionStatus = "Disconnected";
        CurrentDatabase = "";
        ActiveConnectionName = string.Empty;
        StatusBarText = "Disconnected";
    }

    [RelayCommand]
    private void NewQuery()
    {
        if (!IsConnected) return;

        var tab = new QueryTabViewModel(_queryExecutionService)
        {
            Title = $"Query {QueryTabs.Count + 1}",
            ConnectionId = ActiveConnectionId,
            DatabaseName = string.IsNullOrEmpty(CurrentDatabase) ? "master" : CurrentDatabase
        };

        QueryTabs.Add(tab);
        SelectedTab = tab;
    }

    [RelayCommand]
    private async Task ExecuteQueryAsync()
    {
        if (SelectedTab is null) return;
        await SelectedTab.ExecuteQueryCommand.ExecuteAsync(null);
        StatusBarText = SelectedTab.StatusMessage;
    }

    [RelayCommand]
    private void CancelQuery()
    {
        SelectedTab?.CancelQueryCommand.Execute(null);
    }

    [RelayCommand]
    private void CloseTab()
    {
        if (SelectedTab is null) return;
        var index = QueryTabs.IndexOf(SelectedTab);
        QueryTabs.Remove(SelectedTab);
        if (QueryTabs.Count > 0)
            SelectedTab = QueryTabs[Math.Min(index, QueryTabs.Count - 1)];
    }

    [RelayCommand]
    private void ToggleTheme()
    {
        IsDarkTheme = !IsDarkTheme;
        if (Application.Current != null)
        {
            Application.Current.RequestedThemeVariant = IsDarkTheme ? ThemeVariant.Dark : ThemeVariant.Light;
        }
        _settingsService.Theme = IsDarkTheme ? "Dark" : "Light";
        _settingsService.Save();
    }

    [RelayCommand]
    private async Task ExportResultsAsync()
    {
        if (SelectedTab?.LastResult == null || SaveFileRequested == null) return;

        var (result, filePath) = await SaveFileRequested.Invoke();
        if (!result) return;

        await _importExportService.ExportToCsvAsync(
            SelectedTab.LastResult,
            filePath,
            new ExportOptions { IncludeHeaders = true });

        StatusBarText = $"Exported to {filePath}";
    }

    public void OpenScriptInNewTab(string script, string title = "Script")
    {
        var tab = new QueryTabViewModel(_queryExecutionService)
        {
            Title = title,
            SqlText = script,
            ConnectionId = ActiveConnectionId,
            DatabaseName = string.IsNullOrEmpty(CurrentDatabase) ? "master" : CurrentDatabase
        };

        QueryTabs.Add(tab);
        SelectedTab = tab;
    }

    private void OnConnectionOpened(object? sender, Guid connectionId)
    {
        StatusBarText = "Connection established";
    }

    private void OnConnectionClosed(object? sender, Guid connectionId)
    {
        if (connectionId == ActiveConnectionId)
        {
            IsConnected = false;
            ConnectionStatus = "Disconnected";
        }
    }
}
