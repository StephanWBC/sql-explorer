using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Microsoft.Extensions.DependencyInjection;
using SqlStudio.App.ViewModels;
using SqlStudio.App.Views;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Services;
using SqlStudio.LanguageServices.Interfaces;
using SqlStudio.LanguageServices.Services;

namespace SqlStudio.App;

public partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        // Global exception handlers — prevent crashes from unhandled exceptions
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            Console.Error.WriteLine($"[FATAL] Unhandled: {args.ExceptionObject}");
        };
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Console.Error.WriteLine($"[WARN] Unobserved task: {args.Exception?.Message}");
            args.SetObserved(); // Prevent crash
        };

        var services = new ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow
            {
                DataContext = Services.GetRequiredService<MainWindowViewModel>()
            };
        }

        base.OnFrameworkInitializationCompleted();
    }

    private static void ConfigureServices(IServiceCollection services)
    {
        // Core services
        services.AddSingleton<IConnectionManager, ConnectionManager>();
        services.AddSingleton<IConnectionStore, ConnectionStore>();
        services.AddSingleton<ISettingsService, SettingsService>();
        services.AddTransient<IQueryExecutionService, QueryExecutionService>();
        services.AddTransient<IObjectExplorerService, ObjectExplorerService>();
        services.AddTransient<IScriptGenerationService, ScriptGenerationService>();
        services.AddTransient<IImportExportService, ImportExportService>();

        // Language services
        services.AddSingleton<ISchemaCacheService, SchemaCacheService>();
        services.AddSingleton<ICompletionProvider, SqlCompletionProvider>();
        services.AddSingleton<ISqlTokenizer, SqlTokenizer>();

        // ViewModels
        services.AddTransient<MainWindowViewModel>();
        services.AddTransient<ConnectionDialogViewModel>();
        services.AddTransient<ConnectionManagerViewModel>();
    }
}
