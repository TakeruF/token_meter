using System.Text.Json;

namespace TokenMeter.Core;

internal static class JsonElementExtensions
{
    public static JsonElement? PropertyOrNull(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value)
            ? value
            : null;

    public static string? StringOrNull(this JsonElement? element) =>
        element is { ValueKind: JsonValueKind.String } value ? value.GetString() : null;

    public static long? Int64OrNull(this JsonElement? element)
    {
        if (element is not { } value || value.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        if (value.TryGetInt64(out var integer))
        {
            return integer;
        }

        return value.TryGetDouble(out var number) ? checked((long)number) : null;
    }

    public static long? Int64OrNull(this JsonElement element) =>
        ((JsonElement?)element).Int64OrNull();

    public static double? DoubleOrNull(this JsonElement? element)
    {
        if (element is not { } value || value.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        return value.TryGetDouble(out var number) ? number : null;
    }

    public static double? DoubleOrNull(this JsonElement element) =>
        ((JsonElement?)element).DoubleOrNull();
}
