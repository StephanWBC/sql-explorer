using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;

namespace SqlStudio.App.ViewModels;

public class BoolToStatusBgConverter : IValueConverter
{
    public static readonly BoolToStatusBgConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? new SolidColorBrush(Color.Parse("#2A1010")) : new SolidColorBrush(Color.Parse("#0A2A10"));
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BoolToStatusIconConverter : IValueConverter
{
    public static readonly BoolToStatusIconConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? "\u274C" : "\u2705";
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BoolToTestTextConverter : IValueConverter
{
    public static readonly BoolToTestTextConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? "Testing..." : "Test Connection";
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BoolToConnectTextConverter : IValueConverter
{
    public static readonly BoolToConnectTextConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? "Connecting..." : "Connect";
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BoolToSignInTextConverter : IValueConverter
{
    public static readonly BoolToSignInTextConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? "Opening browser..." : "Sign in with Microsoft";
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BoolToConnectionDotConverter : IValueConverter
{
    public static readonly BoolToConnectionDotConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Color.Parse("#3FB950") : Color.Parse("#484F58");
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}

public class BoolToFontWeightConverter : IValueConverter
{
    public static readonly BoolToFontWeightConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Avalonia.Media.FontWeight.Bold : Avalonia.Media.FontWeight.Normal;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}
