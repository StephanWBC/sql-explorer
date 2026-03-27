namespace SqlStudio.Core.Interfaces;

public interface ISettingsService
{
    string Theme { get; set; }
    string EditorFontFamily { get; set; }
    int EditorFontSize { get; set; }
    int MaxResultRows { get; set; }
    int CommandTimeoutSeconds { get; set; }
    void Save();
    void Load();
}
