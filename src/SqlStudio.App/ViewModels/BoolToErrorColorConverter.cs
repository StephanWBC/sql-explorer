using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;

namespace SqlStudio.App.ViewModels;

public class BoolToErrorColorConverter : IValueConverter
{
    public static readonly BoolToErrorColorConverter Instance = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is true)
            return new SolidColorBrush(Color.Parse("#FF4444"));
        return new SolidColorBrush(Color.Parse("#44BB44"));
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        throw new NotImplementedException();
    }
}
