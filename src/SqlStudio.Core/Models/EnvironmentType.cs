namespace SqlStudio.Core.Models;

public static class EnvironmentType
{
    public static string GetColor(string? label) => Normalize(label) switch
    {
        var s when s.Contains("prod") => "#F85149",
        var s when s.Contains("staging") || s.Contains("stg") || s.Contains("uat") => "#D29922",
        var s when s.Contains("dev") => "#3FB950",
        var s when s.Contains("test") || s.Contains("qa") => "#58A6FF",
        var s when s.Contains("local") || s.Contains("docker") => "#8B949E",
        _ => "#8B949E"
    };

    public static string GetBadgeBg(string? label) => Normalize(label) switch
    {
        var s when s.Contains("prod") => "#2D1518",
        var s when s.Contains("staging") || s.Contains("stg") || s.Contains("uat") => "#2D2410",
        var s when s.Contains("dev") => "#122117",
        var s when s.Contains("test") || s.Contains("qa") => "#12202D",
        _ => "#1A1F24"
    };

    public static readonly string[] Presets =
        ["Development", "Staging", "Production", "Staging - NAM", "Production - NAM", "Custom"];

    private static string Normalize(string? label) =>
        label?.Trim().ToLowerInvariant() ?? "";
}
