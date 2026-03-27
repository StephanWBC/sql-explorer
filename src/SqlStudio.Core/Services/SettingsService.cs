using System.Text.Json;
using SqlStudio.Core.Interfaces;

namespace SqlStudio.Core.Services;

public class SettingsService : ISettingsService
{
    private static readonly string SettingsDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sqlexplorer");
    private static readonly string SettingsFile = Path.Combine(SettingsDir, "settings.json");

    public string Theme { get; set; } = "Dark";
    public string EditorFontFamily { get; set; } = "Cascadia Code, JetBrains Mono, Consolas, monospace";
    public int EditorFontSize { get; set; } = 14;
    public int MaxResultRows { get; set; } = 50000;
    public int CommandTimeoutSeconds { get; set; } = 60;

    public SettingsService()
    {
        Load();
    }

    public void Save()
    {
        Directory.CreateDirectory(SettingsDir);
        var json = JsonSerializer.Serialize(new SettingsData
        {
            Theme = Theme,
            EditorFontFamily = EditorFontFamily,
            EditorFontSize = EditorFontSize,
            MaxResultRows = MaxResultRows,
            CommandTimeoutSeconds = CommandTimeoutSeconds
        }, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(SettingsFile, json);
    }

    public void Load()
    {
        if (!File.Exists(SettingsFile)) return;
        try
        {
            var json = File.ReadAllText(SettingsFile);
            var data = JsonSerializer.Deserialize<SettingsData>(json);
            if (data == null) return;
            Theme = data.Theme;
            EditorFontFamily = data.EditorFontFamily;
            EditorFontSize = data.EditorFontSize;
            MaxResultRows = data.MaxResultRows;
            CommandTimeoutSeconds = data.CommandTimeoutSeconds;
        }
        catch { /* use defaults */ }
    }

    private class SettingsData
    {
        public string Theme { get; set; } = "Dark";
        public string EditorFontFamily { get; set; } = "Cascadia Code, JetBrains Mono, Consolas, monospace";
        public int EditorFontSize { get; set; } = 14;
        public int MaxResultRows { get; set; } = 50000;
        public int CommandTimeoutSeconds { get; set; } = 60;
    }
}
