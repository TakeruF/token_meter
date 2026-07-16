using System.Globalization;

namespace TokenMeter.Core;

public sealed class UsageAggregator
{
    public UsageAggregator(TimeZoneInfo? timeZone = null)
    {
        TimeZone = timeZone ?? TimeZoneInfo.Local;
    }

    public TimeZoneInfo TimeZone { get; }

    public DateTimeOffset StartOfDay(DateTimeOffset date)
    {
        var local = TimeZoneInfo.ConvertTime(date, TimeZone);
        return AtLocal(new DateTime(local.Year, local.Month, local.Day));
    }

    public DateTimeOffset Day(int offsetFromToday, DateTimeOffset? now = null) =>
        StartOfDay(now ?? DateTimeOffset.Now).AddDays(-offsetFromToday);

    public DateTimeOffset StartOfHour(DateTimeOffset date)
    {
        var local = TimeZoneInfo.ConvertTime(date, TimeZone);
        return AtLocal(new DateTime(local.Year, local.Month, local.Day, local.Hour, 0, 0));
    }

    public long TotalTokens(IEnumerable<UsageEvent> events) => events.Sum(item => item.TotalTokens);

    public DailyUsage? TodayTotals(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        DateTimeOffset? now = null)
    {
        var start = StartOfDay(now ?? DateTimeOffset.Now);
        var matching = events.Where(item => item.Provider == provider && item.Timestamp >= start).ToArray();
        return matching.Length == 0 ? null : Combine(matching, start, provider);
    }

    public IReadOnlyList<DailyUsage> DailyUsage(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        int days,
        DateTimeOffset? now = null)
    {
        if (days <= 0)
        {
            return [];
        }

        var cutoff = Day(days - 1, now);
        return events
            .Where(item => item.Provider == provider && item.Timestamp >= cutoff)
            .GroupBy(item => StartOfDay(item.Timestamp))
            .Select(group => Combine(group, group.Key, provider))
            .OrderBy(item => item.Day)
            .ToArray();
    }

    public IReadOnlyList<DailyUsage> DailySeries(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        int days,
        DateTimeOffset? now = null)
    {
        var existing = DailyUsage(events, provider, days, now).ToDictionary(item => item.Day);
        return Enumerable.Range(0, Math.Max(0, days))
            .Reverse()
            .Select(offset =>
            {
                var day = Day(offset, now);
                return existing.GetValueOrDefault(day) ?? Empty(day, provider);
            })
            .ToArray();
    }

    public IReadOnlyList<DailyUsage> HourlySeries(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var start = StartOfDay(current);
        var localNow = TimeZoneInfo.ConvertTime(current, TimeZone);
        var existing = events
            .Where(item => item.Provider == provider && item.Timestamp >= start)
            .GroupBy(item => StartOfHour(item.Timestamp))
            .ToDictionary(group => group.Key, group => Combine(group, group.Key, provider));

        return Enumerable.Range(0, localNow.Hour + 1)
            .Select(hour =>
            {
                var bucket = AtLocal(new DateTime(localNow.Year, localNow.Month, localNow.Day, hour, 0, 0));
                return existing.GetValueOrDefault(bucket) ?? Empty(bucket, provider);
            })
            .ToArray();
    }

    public TokenWindowUsage? SessionBlock(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        TimeSpan? length = null,
        DateTimeOffset? now = null)
    {
        var duration = length ?? TimeSpan.FromHours(5);
        var matching = events
            .Where(item => item.Provider == provider)
            .OrderBy(item => item.Timestamp)
            .ToArray();
        if (matching.Length == 0)
        {
            return null;
        }

        var blockStart = matching[0].Timestamp;
        long blockTokens = 0;
        foreach (var item in matching)
        {
            if (item.Timestamp >= blockStart + duration)
            {
                blockStart = item.Timestamp;
                blockTokens = 0;
            }
            blockTokens += item.TotalTokens;
        }

        var resetsAt = blockStart + duration;
        if (resetsAt <= (now ?? DateTimeOffset.Now))
        {
            return null;
        }

        return new TokenWindowUsage(
            blockStart,
            resetsAt,
            blockTokens,
            TokenWindowBoundary.Inferred,
            checked((int)duration.TotalMinutes));
    }

    public TokenWindowUsage? ReportedWindowUsage(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        UsageWindow window)
    {
        if (window.ResetsAt is null || window.WindowMinutes is null)
        {
            return null;
        }

        var start = window.ResetsAt.Value.AddMinutes(-window.WindowMinutes.Value);
        var tokens = events
            .Where(item =>
                item.Provider == provider && item.Timestamp >= start && item.Timestamp <= window.ResetsAt)
            .Sum(item => item.TotalTokens);
        return new TokenWindowUsage(
            start,
            window.ResetsAt,
            tokens,
            TokenWindowBoundary.Reported,
            window.WindowMinutes);
    }

    public TokenWindowUsage? RollingWindowUsage(
        IEnumerable<UsageEvent> events,
        UsageProviderId provider,
        int days,
        DateTimeOffset? now = null)
    {
        var start = Day(days - 1, now);
        var matching = events
            .Where(item => item.Provider == provider && item.Timestamp >= start)
            .ToArray();
        return matching.Length == 0
            ? null
            : new TokenWindowUsage(
                start,
                null,
                matching.Sum(item => item.TotalTokens),
                TokenWindowBoundary.Rolling,
                days * 24 * 60);
    }

    public IReadOnlyList<ModelUsage> ModelBreakdown(
        IEnumerable<UsageEvent> events,
        UsageProviderId? provider = null) => events
        .Where(item =>
            (provider is null || item.Provider == provider) && !string.IsNullOrWhiteSpace(item.Model))
        .GroupBy(item => (Provider: item.Provider, Model: item.Model!))
        .Select(group => new ModelUsage(group.Key.Model, group.Key.Provider, group.Sum(item => item.WorkingTokens)))
        .OrderByDescending(item => item.TotalTokens)
        .ToArray();

    public IReadOnlyList<SessionSummary> RecentSessions(
        IEnumerable<UsageEvent> events,
        int limit = 20) => events
        .GroupBy(item => (item.Provider, Session: item.SessionId ?? item.Id))
        .Select(Summarize)
        .OrderByDescending(item => item.End)
        .Take(limit)
        .ToArray();

    public static string AbbreviateTokens(long tokens)
    {
        var absolute = Math.Abs((double)tokens);
        return absolute switch
        {
            >= 1_000_000_000 => (tokens / 1_000_000_000d).ToString("0.00", CultureInfo.InvariantCulture) + "B",
            >= 1_000_000 => (tokens / 1_000_000d).ToString("0.00", CultureInfo.InvariantCulture) + "M",
            >= 1_000 => (tokens / 1_000d).ToString("0.0", CultureInfo.InvariantCulture) + "K",
            _ => tokens.ToString(CultureInfo.InvariantCulture),
        };
    }

    private SessionSummary Summarize(IGrouping<(UsageProviderId Provider, string Session), UsageEvent> group)
    {
        var items = group.ToArray();
        var reasoning = items.Any(item => item.ReasoningTokens is not null)
            ? items.Sum(item => item.ReasoningTokens ?? 0)
            : (long?)null;
        var model = items
            .Where(item => !string.IsNullOrWhiteSpace(item.Model))
            .GroupBy(item => item.Model)
            .MaxBy(item => item.Count())?
            .Key;

        return new SessionSummary(
            $"{group.Key.Provider.StorageValue()}|{group.Key.Session}",
            group.Key.Provider,
            items.Min(item => item.Timestamp),
            items.Max(item => item.Timestamp),
            items.Length,
            model,
            items.Sum(item => item.InputTokens),
            items.Sum(item => item.CachedInputTokens),
            items.Sum(item => item.CacheCreationTokens),
            items.Sum(item => item.OutputTokens),
            reasoning,
            items.Sum(item => item.TotalTokens));
    }

    private static DailyUsage Combine(
        IEnumerable<UsageEvent> events,
        DateTimeOffset day,
        UsageProviderId provider)
    {
        var items = events.ToArray();
        var reasoning = items.Any(item => item.ReasoningTokens is not null)
            ? items.Sum(item => item.ReasoningTokens ?? 0)
            : (long?)null;
        return new DailyUsage(
            day,
            provider,
            items.Sum(item => item.InputTokens),
            items.Sum(item => item.CachedInputTokens),
            items.Sum(item => item.CacheCreationTokens),
            items.Sum(item => item.OutputTokens),
            reasoning,
            items.Sum(item => item.TotalTokens));
    }

    private static DailyUsage Empty(DateTimeOffset date, UsageProviderId provider) =>
        new(date, provider, 0, 0, 0, 0, null, 0);

    private DateTimeOffset AtLocal(DateTime localDate)
    {
        var unspecified = DateTime.SpecifyKind(localDate, DateTimeKind.Unspecified);
        if (TimeZone.IsInvalidTime(unspecified))
        {
            unspecified = unspecified.AddHours(1);
        }
        return new DateTimeOffset(unspecified, TimeZone.GetUtcOffset(unspecified));
    }
}
