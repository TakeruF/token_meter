using Windows.ApplicationModel.Resources;

namespace TokenMeter.Windows;

public static class L
{
    private static readonly ResourceLoader Loader = ResourceLoader.GetForViewIndependentUse();

    public static string Get(string key)
    {
        var value = Loader.GetString(key);
        return string.IsNullOrWhiteSpace(value) ? key : value;
    }
}

public static class DisplayFormatting
{
    public static string Tokens(long value) => UsageAggregator.AbbreviateTokens(value);

    public static string Percent(double ratio) => $"{Math.Clamp(ratio, 0, 1):P0}";

    public static string RelativeReset(DateTimeOffset? resetsAt)
    {
        if (resetsAt is null)
        {
            return L.Get("NoResetTime");
        }

        var remaining = resetsAt.Value - DateTimeOffset.Now;
        if (remaining <= TimeSpan.Zero)
        {
            return L.Get("ResetDue");
        }

        if (remaining.TotalDays >= 1)
        {
            return string.Format(
                System.Globalization.CultureInfo.CurrentCulture,
                L.Get("ResetsInDaysHours"),
                (int)remaining.TotalDays,
                remaining.Hours);
        }

        return string.Format(
            System.Globalization.CultureInfo.CurrentCulture,
            L.Get("ResetsInHoursMinutes"),
            (int)remaining.TotalHours,
            remaining.Minutes);
    }
}
