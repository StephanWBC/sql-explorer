using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

/// Represents a group or ungrouped section in the connection manager
public partial class ConnectionGroupItem : ViewModelBase
{
    [ObservableProperty] private string _name;
    [ObservableProperty] private bool _isExpanded = true;
    [ObservableProperty] private bool _isEditing;
    [ObservableProperty] private string _editName = string.Empty;

    public Guid? GroupId { get; }
    public bool IsUngrouped => GroupId == null;
    public ObservableCollection<ConnectionItem> Connections { get; } = new();

    public ConnectionGroupItem(ConnectionGroup? group)
    {
        GroupId = group?.Id;
        _name = group?.Name ?? "Ungrouped";
    }
}

/// Represents a single saved connection in the manager
public partial class ConnectionItem : ViewModelBase
{
    [ObservableProperty] private string _name;
    [ObservableProperty] private string _server;
    [ObservableProperty] private string _database;
    [ObservableProperty] private string? _environmentLabel;
    [ObservableProperty] private bool _isSelected;

    public Guid ConnectionId { get; }
    public Guid? GroupId { get; set; }
    public SavedConnection SavedConnection { get; }

    public string EnvironmentColor => EnvironmentType.GetColor(EnvironmentLabel);
    public string EnvironmentBadgeBg => EnvironmentType.GetBadgeBg(EnvironmentLabel);
    public bool HasEnvironment => !string.IsNullOrWhiteSpace(EnvironmentLabel);
    public string Subtitle => $"{Server}  /  {Database}";

    public ConnectionItem(SavedConnection saved)
    {
        SavedConnection = saved;
        ConnectionId = saved.Id;
        GroupId = saved.GroupId;
        _name = saved.Name;
        _server = saved.Server;
        _database = saved.Database;
        _environmentLabel = saved.EnvironmentLabel;
    }
}

public partial class ConnectionManagerViewModel : ViewModelBase
{
    private readonly IConnectionStore _connectionStore;

    [ObservableProperty] private ConnectionItem? _selectedConnection;
    [ObservableProperty] private ConnectionGroupItem? _selectedGroup;
    [ObservableProperty] private string _statusMessage = string.Empty;
    [ObservableProperty] private bool _hasChanges;

    public ObservableCollection<ConnectionGroupItem> Groups { get; } = new();
    public ObservableCollection<string> EnvironmentPresets { get; } = new(EnvironmentType.Presets);

    public bool DialogResult { get; private set; }
    public event EventHandler? CloseRequested;

    public ConnectionManagerViewModel(IConnectionStore connectionStore)
    {
        _connectionStore = connectionStore;
        _ = SafeLoadAsync();
    }

    private async Task SafeLoadAsync()
    {
        try { await LoadAsync(); }
        catch (Exception ex) { StatusMessage = $"Load error: {ex.Message}"; }
    }

    private async Task LoadAsync()
    {
        Groups.Clear();
        var groups = await _connectionStore.GetGroupsAsync();
        var connections = await _connectionStore.GetAllAsync();

        // Create group items
        foreach (var g in groups)
        {
            var item = new ConnectionGroupItem(g);
            foreach (var c in connections.Where(c => c.GroupId == g.Id))
                item.Connections.Add(new ConnectionItem(c));
            Groups.Add(item);
        }

        // Ungrouped connections
        var ungrouped = connections.Where(c => c.GroupId == null || !groups.Any(g => g.Id == c.GroupId)).ToList();
        if (ungrouped.Count > 0)
        {
            var ungroupedItem = new ConnectionGroupItem(null);
            foreach (var c in ungrouped)
                ungroupedItem.Connections.Add(new ConnectionItem(c));
            Groups.Add(ungroupedItem);
        }
    }

    // ── Group operations ──────────────────────────────────────────────

    [RelayCommand]
    private async Task CreateGroupAsync()
    {
        var group = new ConnectionGroup { Name = "New Group" };
        await _connectionStore.SaveGroupAsync(group);
        var item = new ConnectionGroupItem(group);
        // Insert before ungrouped
        var insertIdx = Groups.Count;
        for (var i = 0; i < Groups.Count; i++)
        {
            if (Groups[i].IsUngrouped) { insertIdx = i; break; }
        }
        Groups.Insert(insertIdx, item);
        SelectedGroup = item;
        HasChanges = true;
        StatusMessage = $"Created group \"{group.Name}\"";
    }

    [RelayCommand]
    private async Task RenameGroupAsync()
    {
        if (SelectedGroup == null || SelectedGroup.IsUngrouped) return;
        SelectedGroup.IsEditing = true;
        SelectedGroup.EditName = SelectedGroup.Name;
    }

    [RelayCommand]
    private async Task ConfirmRenameGroupAsync()
    {
        if (SelectedGroup == null || !SelectedGroup.IsEditing) return;
        var newName = SelectedGroup.EditName.Trim();
        if (string.IsNullOrEmpty(newName)) return;

        SelectedGroup.Name = newName;
        SelectedGroup.IsEditing = false;

        if (SelectedGroup.GroupId != null)
        {
            var groups = await _connectionStore.GetGroupsAsync();
            var group = groups.FirstOrDefault(g => g.Id == SelectedGroup.GroupId);
            if (group != null)
            {
                group.Name = newName;
                await _connectionStore.SaveGroupAsync(group);
            }
        }
        HasChanges = true;
        StatusMessage = $"Renamed to \"{newName}\"";
    }

    [RelayCommand]
    private async Task DeleteGroupAsync()
    {
        if (SelectedGroup == null || SelectedGroup.IsUngrouped) return;

        var groupId = SelectedGroup.GroupId!.Value;

        // Move connections to ungrouped
        var ungrouped = Groups.FirstOrDefault(g => g.IsUngrouped);
        if (ungrouped == null)
        {
            ungrouped = new ConnectionGroupItem(null);
            Groups.Add(ungrouped);
        }
        foreach (var conn in SelectedGroup.Connections.ToList())
        {
            conn.GroupId = null;
            conn.SavedConnection.GroupId = null;
            await _connectionStore.SaveAsync(conn.SavedConnection);
            ungrouped.Connections.Add(conn);
        }

        await _connectionStore.DeleteGroupAsync(groupId);
        Groups.Remove(SelectedGroup);
        SelectedGroup = null;
        HasChanges = true;
        StatusMessage = "Group deleted. Connections moved to Ungrouped.";
    }

    // ── Connection operations ─────────────────────────────────────────

    [RelayCommand]
    private async Task DeleteConnectionAsync()
    {
        if (SelectedConnection == null) return;

        await _connectionStore.DeleteAsync(SelectedConnection.ConnectionId);

        // Remove from its group
        foreach (var g in Groups)
        {
            if (g.Connections.Remove(SelectedConnection))
                break;
        }

        StatusMessage = $"Deleted \"{SelectedConnection.Name}\"";
        SelectedConnection = null;
        HasChanges = true;
    }

    [RelayCommand]
    private async Task MoveConnectionToGroupAsync(ConnectionGroupItem? targetGroup)
    {
        if (SelectedConnection == null || targetGroup == null) return;

        // Remove from current group
        foreach (var g in Groups)
            g.Connections.Remove(SelectedConnection);

        // Add to target
        SelectedConnection.GroupId = targetGroup.GroupId;
        SelectedConnection.SavedConnection.GroupId = targetGroup.GroupId;
        await _connectionStore.SaveAsync(SelectedConnection.SavedConnection);
        targetGroup.Connections.Add(SelectedConnection);

        HasChanges = true;
        StatusMessage = $"Moved \"{SelectedConnection.Name}\" to \"{targetGroup.Name}\"";
    }

    [RelayCommand]
    private async Task ChangeEnvironmentAsync(string? env)
    {
        if (SelectedConnection == null) return;

        SelectedConnection.EnvironmentLabel = env;
        SelectedConnection.SavedConnection.EnvironmentLabel = env;
        await _connectionStore.SaveAsync(SelectedConnection.SavedConnection);

        HasChanges = true;
        StatusMessage = $"Set environment to \"{env}\"";
    }

    [RelayCommand]
    private async Task MoveConnectionUpAsync()
    {
        if (SelectedConnection == null) return;
        var group = Groups.FirstOrDefault(g => g.Connections.Contains(SelectedConnection));
        if (group == null) return;
        var idx = group.Connections.IndexOf(SelectedConnection);
        if (idx > 0)
            group.Connections.Move(idx, idx - 1);
    }

    [RelayCommand]
    private async Task MoveConnectionDownAsync()
    {
        if (SelectedConnection == null) return;
        var group = Groups.FirstOrDefault(g => g.Connections.Contains(SelectedConnection));
        if (group == null) return;
        var idx = group.Connections.IndexOf(SelectedConnection);
        if (idx < group.Connections.Count - 1)
            group.Connections.Move(idx, idx + 1);
    }

    [RelayCommand]
    private void Close()
    {
        DialogResult = true;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }
}
