using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public partial class ObjectExplorerNodeViewModel : ViewModelBase
{
    private readonly IObjectExplorerService? _objectExplorerService;
    private readonly IScriptGenerationService? _scriptService;

    [ObservableProperty] private string _name = string.Empty;
    [ObservableProperty] private DatabaseObjectType _objectType;
    [ObservableProperty] private bool _isExpanded;
    [ObservableProperty] private bool _isLoading;

    // Environment badge
    [ObservableProperty] private string? _environmentLabel;
    [ObservableProperty] private bool _hasEnvironmentLabel;
    [ObservableProperty] private bool _isGroupNode;

    public DatabaseObject Model { get; }
    public ObservableCollection<ObjectExplorerNodeViewModel> Children { get; } = new();

    public event EventHandler<string>? ScriptRequested;
    public event EventHandler<(Guid ConnectionId, string Database, string Sql)>? ExecuteRequested;

    public ObjectExplorerNodeViewModel(
        DatabaseObject model,
        IObjectExplorerService? objectExplorerService = null,
        IScriptGenerationService? scriptService = null,
        string? environmentLabel = null)
    {
        Model = model;
        _objectExplorerService = objectExplorerService;
        _scriptService = scriptService;
        Name = model.Name;
        ObjectType = model.ObjectType;
        EnvironmentLabel = environmentLabel;
        HasEnvironmentLabel = !string.IsNullOrWhiteSpace(environmentLabel);
        IsGroupNode = model.ObjectType == DatabaseObjectType.ConnectionGroup;

        if (model.IsExpandable && !model.IsLoaded)
        {
            Children.Add(new ObjectExplorerNodeViewModel(new DatabaseObject { Name = "Loading..." }));
        }
    }

    partial void OnIsExpandedChanged(bool value)
    {
        if (value && Model.IsExpandable && !Model.IsLoaded)
        {
            _ = LoadChildrenAsync();
        }
    }

    private async Task LoadChildrenAsync()
    {
        if (_objectExplorerService == null) return;

        IsLoading = true;
        Children.Clear();

        try
        {
            switch (Model.ObjectType)
            {
                case DatabaseObjectType.Server:
                    await LoadDatabasesAsync();
                    break;
                case DatabaseObjectType.Database:
                    LoadDatabaseFolders();
                    break;
                case DatabaseObjectType.Folder:
                    await LoadFolderContentsAsync();
                    break;
                case DatabaseObjectType.Table:
                case DatabaseObjectType.View:
                    await LoadTableDetailsAsync();
                    break;
                case DatabaseObjectType.ConnectionGroup:
                    // Group children are managed externally by MainWindowViewModel
                    break;
            }
        }
        catch (Exception ex)
        {
            Children.Add(new ObjectExplorerNodeViewModel(new DatabaseObject { Name = $"Error: {ex.Message}" }));
        }
        finally
        {
            Model.IsLoaded = true;
            IsLoading = false;
        }
    }

    private async Task LoadDatabasesAsync()
    {
        var databases = await _objectExplorerService!.GetDatabasesAsync(Model.ConnectionId);
        foreach (var db in databases)
        {
            Children.Add(new ObjectExplorerNodeViewModel(
                new DatabaseObject
                {
                    Name = db,
                    ConnectionId = Model.ConnectionId,
                    ObjectType = DatabaseObjectType.Database,
                    IsExpandable = true,
                    Database = db
                }, _objectExplorerService, _scriptService));
        }
    }

    private void LoadDatabaseFolders()
    {
        string[] folders = ["Tables", "Views", "Stored Procedures", "Functions"];
        foreach (var folder in folders)
        {
            Children.Add(new ObjectExplorerNodeViewModel(
                new DatabaseObject
                {
                    Name = folder,
                    ConnectionId = Model.ConnectionId,
                    ObjectType = DatabaseObjectType.Folder,
                    IsExpandable = true,
                    Database = Model.Database
                }, _objectExplorerService, _scriptService));
        }
    }

    private async Task LoadFolderContentsAsync()
    {
        switch (Model.Name)
        {
            case "Tables":
                var tables = await _objectExplorerService!.GetTablesAsync(Model.ConnectionId, Model.Database);
                foreach (var t in tables)
                {
                    Children.Add(new ObjectExplorerNodeViewModel(
                        new DatabaseObject
                        {
                            Name = $"{t.Schema}.{t.Name}",
                            Schema = t.Schema,
                            ConnectionId = Model.ConnectionId,
                            ObjectType = DatabaseObjectType.Table,
                            IsExpandable = true,
                            Database = Model.Database
                        }, _objectExplorerService, _scriptService));
                }
                break;

            case "Views":
                var views = await _objectExplorerService!.GetViewsAsync(Model.ConnectionId, Model.Database);
                foreach (var v in views)
                {
                    Children.Add(new ObjectExplorerNodeViewModel(
                        new DatabaseObject
                        {
                            Name = $"{v.Schema}.{v.Name}",
                            Schema = v.Schema,
                            ConnectionId = Model.ConnectionId,
                            ObjectType = DatabaseObjectType.View,
                            IsExpandable = false,
                            Database = Model.Database
                        }, _objectExplorerService, _scriptService));
                }
                break;

            case "Stored Procedures":
                var procs = await _objectExplorerService!.GetStoredProceduresAsync(Model.ConnectionId, Model.Database);
                foreach (var p in procs)
                {
                    Children.Add(new ObjectExplorerNodeViewModel(
                        new DatabaseObject
                        {
                            Name = $"{p.Schema}.{p.Name}",
                            Schema = p.Schema,
                            ConnectionId = Model.ConnectionId,
                            ObjectType = DatabaseObjectType.StoredProcedure,
                            IsExpandable = false,
                            Database = Model.Database
                        }, _objectExplorerService, _scriptService));
                }
                break;

            case "Functions":
                var funcs = await _objectExplorerService!.GetFunctionsAsync(Model.ConnectionId, Model.Database);
                foreach (var f in funcs)
                {
                    Children.Add(new ObjectExplorerNodeViewModel(
                        new DatabaseObject
                        {
                            Name = $"{f.Schema}.{f.Name}",
                            Schema = f.Schema,
                            ConnectionId = Model.ConnectionId,
                            ObjectType = DatabaseObjectType.Function,
                            IsExpandable = false,
                            Database = Model.Database
                        }, _objectExplorerService, _scriptService));
                }
                break;

            case "Columns":
                break;
        }
    }

    private async Task LoadTableDetailsAsync()
    {
        var schema = Model.Schema;
        var tableName = Model.Name.Contains('.') ? Model.Name.Split('.').Last() : Model.Name;

        string[] detailFolders = ["Columns", "Keys", "Indexes", "Foreign Keys"];
        foreach (var folder in detailFolders)
        {
            var folderNode = new ObjectExplorerNodeViewModel(
                new DatabaseObject
                {
                    Name = folder,
                    Schema = schema,
                    ConnectionId = Model.ConnectionId,
                    ObjectType = DatabaseObjectType.Folder,
                    IsExpandable = true,
                    Database = Model.Database
                }, _objectExplorerService, _scriptService);

            if (folder == "Columns")
            {
                try
                {
                    var columns = await _objectExplorerService!.GetColumnsAsync(
                        Model.ConnectionId, Model.Database, schema, tableName);
                    foreach (var col in columns)
                    {
                        var pkIndicator = col.IsPrimaryKey ? " (PK)" : "";
                        var nullIndicator = col.IsNullable ? " NULL" : " NOT NULL";
                        folderNode.Children.Add(new ObjectExplorerNodeViewModel(
                            new DatabaseObject
                            {
                                Name = $"{col.Name} ({col.DataType}{pkIndicator}{nullIndicator})",
                                ConnectionId = Model.ConnectionId,
                                ObjectType = DatabaseObjectType.Column,
                                IsExpandable = false,
                                Database = Model.Database
                            }));
                    }
                    folderNode.Model.IsLoaded = true;
                }
                catch { /* will load on expand */ }
            }

            Children.Add(folderNode);
        }
    }
}
