using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Platform.Storage;
using Microsoft.Extensions.DependencyInjection;
using SqlStudio.App.ViewModels;

namespace SqlStudio.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        // Wire up keyboard shortcuts
        KeyDown += OnKeyDown;
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);

        if (DataContext is MainWindowViewModel vm)
        {
            vm.ConnectRequested += OnConnectRequested;
            vm.ManageConnectionsRequested += OnManageConnectionsRequested;
            vm.SaveFileRequested += OnSaveFileRequested;
        }
    }

    private async void OnManageConnectionsRequested(object? sender, EventArgs e)
    {
        var vm = App.Services.GetRequiredService<ConnectionManagerViewModel>();
        var dialog = new ConnectionManagerDialog { DataContext = vm };
        await dialog.ShowDialog(this);
    }

    private async void OnConnectRequested(object? sender, EventArgs e)
    {
        var vm = App.Services.GetRequiredService<ConnectionDialogViewModel>();
        var dialog = new ConnectionDialog { DataContext = vm };

        await dialog.ShowDialog(this);

        if (vm.DialogResult && vm.ResultConnection != null && vm.ResultConnectionId != null)
        {
            var mainVm = (MainWindowViewModel)DataContext!;
            mainVm.OnConnected(vm.ResultConnectionId.Value, vm.ResultConnection, vm.ResultSavedConnection);
        }
    }

    private async Task<(bool Result, string FilePath)> OnSaveFileRequested()
    {
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Export Results",
            DefaultExtension = "csv",
            FileTypeChoices =
            [
                new FilePickerFileType("CSV files") { Patterns = ["*.csv"] },
                new FilePickerFileType("All files") { Patterns = ["*"] }
            ]
        });

        if (file == null) return (false, string.Empty);
        return (true, file.Path.LocalPath);
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (DataContext is not MainWindowViewModel vm) return;

        if (e.Key == Key.F5)
        {
            vm.ExecuteQueryCommand.Execute(null);
            e.Handled = true;
        }
    }
}
