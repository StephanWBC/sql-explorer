namespace SqlStudio.Core.Models;

public static class EnvironmentType
{
    public static string GetColor(string? label) => Normalize(label) switch
    {
        "prod" or "production" or "prd" or "live" => "#F85149",
        "staging" or "stg" or "stage" or "uat" => "#D29922",
        "dev" or "development" or "develop" => "#3FB950",
        "test" or "testing" or "qa" => "#58A6FF",
        "local" or "localhost" or "docker" => "#8B949E",
        _ => "#8B949E"
    };

    public static string GetBadgeBg(string? label) => Normalize(label) switch
    {
        "prod" or "production" or "prd" or "live" => "#2D1518",
        "staging" or "stg" or "stage" or "uat" => "#2D2410",
        "dev" or "development" or "develop" => "#122117",
        "test" or "testing" or "qa" => "#12202D",
        _ => "#1A1F24"
    };

    public static readonly string[] Presets =
        ["prod", "staging", "dev", "test", "qa", "local", "prod-nam", "staging-nam", "dev-nam"];

    private static string Normalize(string? label) =>
        label?.Trim().ToLowerInvariant() ?? "";
}
