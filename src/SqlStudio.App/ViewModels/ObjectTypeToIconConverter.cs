using System.Globalization;
using Avalonia.Data.Converters;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public class ObjectTypeToIconConverter : IValueConverter
{
    public static readonly ObjectTypeToIconConverter Instance = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not DatabaseObjectType objectType) return "?";

        return objectType switch
        {
            DatabaseObjectType.Server => "\U0001F5A5",       // desktop computer
            DatabaseObjectType.Database => "\U0001F4BE",     // floppy disk
            DatabaseObjectType.Table => "\U0001F4CB",        // clipboard
            DatabaseObjectType.View => "\U0001F441",         // eye
            DatabaseObjectType.StoredProcedure => "\u2699",  // gear
            DatabaseObjectType.Function => "\U0001D453",     // italic f
            DatabaseObjectType.Column => "\u2502",           // vertical line
            DatabaseObjectType.Index => "\u2195",            // up-down arrow
            DatabaseObjectType.ForeignKey => "\U0001F517",   // link
            DatabaseObjectType.PrimaryKey => "\U0001F511",   // key
            DatabaseObjectType.Folder => "\U0001F4C1",       // folder
            DatabaseObjectType.Trigger => "\u26A1",          // lightning
            DatabaseObjectType.ConnectionGroup => "\U0001F4E6", // package
            _ => "\u2022"                                     // bullet
        };
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        throw new NotImplementedException();
    }
}
