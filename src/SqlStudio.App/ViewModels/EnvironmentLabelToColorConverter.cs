using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public class EnvironmentLabelToColorConverter : IValueConverter
{
    public static readonly EnvironmentLabelToColorConverter Instance = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var label = value as string;
        var hex = EnvironmentType.GetColor(label);
        return SolidColorBrush.Parse(hex);
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

public class EnvironmentLabelToBgConverter : IValueConverter
{
    public static readonly EnvironmentLabelToBgConverter Instance = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var label = value as string;
        var hex = EnvironmentType.GetBadgeBg(label);
        return SolidColorBrush.Parse(hex);
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}
