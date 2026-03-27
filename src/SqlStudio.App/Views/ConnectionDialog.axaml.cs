using Avalonia.Controls;
using SqlStudio.App.ViewModels;

namespace SqlStudio.App.Views;

public partial class ConnectionDialog : Window
{
    public ConnectionDialog()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);

        if (DataContext is ConnectionDialogViewModel vm)
        {
            vm.CloseRequested += (_, _) => Close();
        }
    }
}
