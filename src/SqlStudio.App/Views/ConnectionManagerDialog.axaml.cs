using Avalonia.Controls;
using SqlStudio.App.ViewModels;

namespace SqlStudio.App.Views;

public partial class ConnectionManagerDialog : Window
{
    public ConnectionManagerDialog()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);

        if (DataContext is ConnectionManagerViewModel vm)
        {
            vm.CloseRequested += (_, _) => Close();
        }
    }
}
