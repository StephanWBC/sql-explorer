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
    private readonly IConnectionStore _connectionStore;
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
    [ObservableProperty] private int _activeConnectionCount;

    private readonly HashSet<Guid> _activeConnectionIds = new();

    public ObservableCollection<ObjectExplorerNodeViewModel> ObjectExplorerNodes { get; } = new();
    public ObservableCollection<QueryTabViewModel> QueryTabs { get; } = new();

    public event EventHandler? ConnectRequested;
    public event Func<Task<(bool Result, string FilePath)>>? SaveFileRequested;
    public event Func<Task<(bool Result, string FilePath)>>? OpenFileRequested;

    public MainWindowViewModel(
        IConnectionManager connectionManager,
        IConnectionStore connectionStore,
        IObjectExplorerService objectExplorerService,
        IQueryExecutionService queryExecutionService,
        IScriptGenerationService scriptService,
        IImportExportService importExportService,
        ISettingsService settingsService)
    {
        _connectionManager = connectionManager;
        _connectionStore = connectionStore;
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

    public void OnConnected(Guid connectionId, ConnectionInfo connectionInfo, SavedConnection? saved = null)
    {
        ActiveConnectionId = connectionId;
        ActiveConnectionName = connectionInfo.Name;
        IsConnected = true;
        ConnectionStatus = $"Connected: {connectionInfo.Server}";
        CurrentDatabase = connectionInfo.Database;
        StatusBarText = $"Connected to {connectionInfo.Server}";
        _activeConnectionIds.Add(connectionId);
        ActiveConnectionCount = _activeConnectionIds.Count;

        // Build display name
        var displayName = string.IsNullOrEmpty(connectionInfo.Database) || connectionInfo.Database == "master"
            ? connectionInfo.Server
            : $"{connectionInfo.Database}  —  {connectionInfo.Server}";

        var serverNode = new ObjectExplorerNodeViewModel(
            new DatabaseObject
            {
                Name = displayName,
                ConnectionId = connectionId,
                ObjectType = DatabaseObjectType.Server,
                IsExpandable = true
            }, _objectExplorerService, _scriptService,
            environmentLabel: saved?.EnvironmentLabel);

        // If the saved connection belongs to a group, nest under group node
        if (saved?.GroupId != null)
        {
            var groupNode = FindOrCreateGroupNode(saved.GroupId.Value);
            if (groupNode != null)
            {
                groupNode.Children.Add(serverNode);
                groupNode.IsExpanded = true;
                return;
            }
        }

        // No group — add at root
        ObjectExplorerNodes.Add(serverNode);
    }

    private ObjectExplorerNodeViewModel? FindOrCreateGroupNode(Guid groupId)
    {
        // Find existing group node
        foreach (var node in ObjectExplorerNodes)
        {
            if (node.IsGroupNode && node.Model.ConnectionId == groupId)
                return node;
        }

        // Create group node — look up name from store
        var groups = _connectionStore.GetGroupsAsync().GetAwaiter().GetResult();
        var group = groups.FirstOrDefault(g => g.Id == groupId);
        if (group == null) return null;

        var groupNode = new ObjectExplorerNodeViewModel(
            new DatabaseObject
            {
                Name = group.Name,
                ConnectionId = groupId, // reuse field for group ID
                ObjectType = DatabaseObjectType.ConnectionGroup,
                IsExpandable = true,
                IsLoaded = true // children managed here, not lazy-loaded
            });
        groupNode.IsExpanded = true;

        // Insert groups at the top
        var insertIdx = 0;
        while (insertIdx < ObjectExplorerNodes.Count && ObjectExplorerNodes[insertIdx].IsGroupNode)
            insertIdx++;
        ObjectExplorerNodes.Insert(insertIdx, groupNode);

        return groupNode;
    }

    [RelayCommand]
    private async Task DisconnectAsync()
    {
        if (ActiveConnectionId == Guid.Empty) return;

        await _connectionManager.DisconnectAsync(ActiveConnectionId);
        _activeConnectionIds.Remove(ActiveConnectionId);
        ActiveConnectionCount = _activeConnectionIds.Count;

        // Remove the specific server node (may be nested in a group)
        RemoveServerNode(ActiveConnectionId);

        if (_activeConnectionIds.Count == 0)
        {
            IsConnected = false;
            ConnectionStatus = "Disconnected";
            CurrentDatabase = "";
            ActiveConnectionName = string.Empty;
            ActiveConnectionId = Guid.Empty;
            StatusBarText = "Disconnected";
            // Clean up empty groups
            CleanupEmptyGroups();
        }
        else
        {
            // Switch to another active connection
            ActiveConnectionId = _activeConnectionIds.First();
            var conn = _connectionManager.ActiveConnections[ActiveConnectionId];
            ActiveConnectionName = conn.Name;
            ConnectionStatus = $"Connected: {conn.Server}";
            CurrentDatabase = conn.Database;
            StatusBarText = $"Connected ({_activeConnectionIds.Count} active)";
        }
    }

    private void RemoveServerNode(Guid connectionId)
    {
        // Check root level
        var rootNode = ObjectExplorerNodes.FirstOrDefault(n =>
            n.ObjectType == DatabaseObjectType.Server && n.Model.ConnectionId == connectionId);
        if (rootNode != null)
        {
            ObjectExplorerNodes.Remove(rootNode);
            return;
        }

        // Check inside groups
        foreach (var group in ObjectExplorerNodes.Where(n => n.IsGroupNode))
        {
            var child = group.Children.FirstOrDefault(n =>
                n.ObjectType == DatabaseObjectType.Server && n.Model.ConnectionId == connectionId);
            if (child != null)
            {
                group.Children.Remove(child);
                return;
            }
        }
    }

    private void CleanupEmptyGroups()
    {
        var emptyGroups = ObjectExplorerNodes.Where(n => n.IsGroupNode && n.Children.Count == 0).ToList();
        foreach (var g in emptyGroups)
            ObjectExplorerNodes.Remove(g);
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
        _activeConnectionIds.Remove(connectionId);
        ActiveConnectionCount = _activeConnectionIds.Count;
        if (connectionId == ActiveConnectionId)
        {
            if (_activeConnectionIds.Count == 0)
            {
                IsConnected = false;
                ConnectionStatus = "Disconnected";
            }
        }
    }
}
