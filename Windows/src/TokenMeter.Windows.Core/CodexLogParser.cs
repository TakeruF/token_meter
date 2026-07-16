using System.Text.Json;

namespace TokenMeter.Core;

public sealed record CodexParseResult(
    IReadOnlyList<UsageEvent> Events,
    CumulativeTotals Totals,
    string? LatestModel,
    long? LatestContextTokens,
    long? ContextWindowTokens,
    UsageWindow? ShortWindow,
    UsageWindow? WeeklyWindow,
    string? PlanType,
    DateTimeOffset? LatestTimestamp,
    DateTimeOffset? LatestRateLimitTimestamp,
    int MalformedLineCount,
    int CandidateLineCount,
    int TotalLineCount);

public sealed record RateLimitParseResult(
    UsageWindow? ShortWindow,
    UsageWindow? WeeklyWindow,
    string? PlanType,
    DateTimeOffset? Timestamp)
{
    public bool HasQuota => ShortWindow is not null || WeeklyWindow is not null;
}

public sealed class CodexLogParser
{
    private readonly IClock _clock;

    public CodexLogParser(IClock? clock = null)
    {
        _clock = clock ?? SystemClock.Instance;
    }

    public CodexParseResult Parse(
        IReadOnlyList<string> lines,
        string sessionId,
        CumulativeTotals? previousTotals = null,
        string? previousModel = null)
    {
        var totals = previousTotals ?? new CumulativeTotals();
        var events = new List<UsageEvent>();
        var currentModel = previousModel;
        string? latestModel = null;
        long? latestContext = null;
        long? contextWindow = null;
        UsageWindow? shortWindow = null;
        UsageWindow? weeklyWindow = null;
        string? planType = null;
        DateTimeOffset? latestTimestamp = null;
        DateTimeOffset? latestRateLimitTimestamp = null;
        var malformed = 0;
        var candidates = 0;

        foreach (var sourceLine in lines)
        {
            var line = sourceLine.Trim();
            if (line.Length == 0 ||
                (!line.Contains("token_count", StringComparison.Ordinal) &&
                 !line.Contains("turn_context", StringComparison.Ordinal)))
            {
                continue;
            }

            candidates++;
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                var type = root.PropertyOrNull("type").StringOrNull();
                var payload = root.PropertyOrNull("payload");
                if (payload is null)
                {
                    continue;
                }

                if (type == "turn_context")
                {
                    var parsedModel = payload.Value.PropertyOrNull("model").StringOrNull();
                    if (!string.IsNullOrEmpty(parsedModel))
                    {
                        currentModel = parsedModel;
                    }
                    continue;
                }

                if (type != "event_msg" ||
                    payload.Value.PropertyOrNull("type").StringOrNull() != "token_count")
                {
                    continue;
                }

                var timestamp = LogDate.Parse(root.PropertyOrNull("timestamp").StringOrNull());
                if (timestamp is null)
                {
                    continue;
                }

                var limits = payload.Value.PropertyOrNull("rate_limits");
                if (limits is not null && TryReadLimits(limits.Value, out var reading))
                {
                    shortWindow = reading.ShortWindow ?? shortWindow;
                    weeklyWindow = reading.WeeklyWindow ?? weeklyWindow;
                    planType = reading.PlanType ?? planType;
                    latestRateLimitTimestamp = timestamp;
                }

                var info = payload.Value.PropertyOrNull("info");
                if (info is null)
                {
                    continue;
                }

                contextWindow = info.Value.PropertyOrNull("model_context_window").Int64OrNull() ?? contextWindow;
                var last = info.Value.PropertyOrNull("last_token_usage");
                latestContext = last?.PropertyOrNull("input_tokens").Int64OrNull() ?? latestContext;
                var cumulative = info.Value.PropertyOrNull("total_token_usage");
                if (cumulative is null)
                {
                    continue;
                }

                var currentInput = cumulative.Value.PropertyOrNull("input_tokens").Int64OrNull() ?? 0;
                var currentCached = cumulative.Value.PropertyOrNull("cached_input_tokens").Int64OrNull() ?? 0;
                var currentOutput = cumulative.Value.PropertyOrNull("output_tokens").Int64OrNull() ?? 0;
                var currentReasoning = cumulative.Value.PropertyOrNull("reasoning_output_tokens").Int64OrNull() ?? 0;
                var currentTotal = cumulative.Value.PropertyOrNull("total_tokens").Int64OrNull() ?? 0;

                var restarted = currentTotal < totals.TotalTokens;
                var deltaInput = restarted ? currentInput : currentInput - totals.InputTokens;
                var deltaCached = restarted ? currentCached : currentCached - totals.CachedInputTokens;
                var deltaOutput = restarted ? currentOutput : currentOutput - totals.OutputTokens;
                var deltaReasoning = restarted ? currentReasoning : currentReasoning - totals.ReasoningTokens;
                var deltaTotal = restarted ? currentTotal : currentTotal - totals.TotalTokens;

                totals = new CumulativeTotals(
                    currentInput,
                    currentCached,
                    currentOutput,
                    currentReasoning,
                    currentTotal,
                    totals.EventCount + 1);
                latestTimestamp = timestamp;
                latestModel = currentModel ?? latestModel;

                if (deltaTotal <= 0)
                {
                    continue;
                }

                events.Add(new UsageEvent(
                    $"{sessionId}|{timestamp.Value.ToUnixTimeMilliseconds()}|{totals.EventCount}",
                    UsageProviderId.Codex,
                    timestamp.Value,
                    currentModel,
                    sessionId,
                    Math.Max(0, deltaInput),
                    Math.Max(0, deltaCached),
                    0,
                    Math.Max(0, deltaOutput),
                    Math.Max(0, deltaReasoning),
                    deltaTotal,
                    UsageSource.LocalLog));
            }
            catch (JsonException)
            {
                malformed++;
            }
        }

        return new CodexParseResult(
            events, totals, latestModel, latestContext, contextWindow,
            shortWindow, weeklyWindow, planType, latestTimestamp,
            latestRateLimitTimestamp, malformed, candidates, lines.Count);
    }

    public RateLimitParseResult ParseLatestRateLimits(IReadOnlyList<string> lines)
    {
        var result = new RateLimitParseResult(null, null, null, null);
        foreach (var line in lines)
        {
            if (!line.Contains("token_count", StringComparison.Ordinal) ||
                !line.Contains("rate_limits", StringComparison.Ordinal))
            {
                continue;
            }

            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                var payload = root.PropertyOrNull("payload");
                var timestamp = LogDate.Parse(root.PropertyOrNull("timestamp").StringOrNull());
                var limits = payload?.PropertyOrNull("rate_limits");
                if (root.PropertyOrNull("type").StringOrNull() != "event_msg" ||
                    payload?.PropertyOrNull("type").StringOrNull() != "token_count" ||
                    timestamp is null || limits is null || !TryReadLimits(limits.Value, out var reading))
                {
                    continue;
                }

                result = new RateLimitParseResult(
                    reading.ShortWindow,
                    reading.WeeklyWindow,
                    reading.PlanType,
                    timestamp);
            }
            catch (JsonException)
            {
                // A live trailing record is allowed to be incomplete.
            }
        }
        return result;
    }

    public static bool IsShortWindow(int? windowMinutes) => windowMinutes is <= 1440;

    private bool TryReadLimits(JsonElement limits, out RateLimitReading reading)
    {
        reading = new RateLimitReading(null, null, limits.PropertyOrNull("plan_type").StringOrNull());
        var limitId = limits.PropertyOrNull("limit_id").StringOrNull();
        if (limitId is not null && limitId != "codex")
        {
            return false;
        }

        foreach (var slot in new[] { "primary", "secondary" })
        {
            var entry = limits.PropertyOrNull(slot);
            if (entry is not { ValueKind: JsonValueKind.Object })
            {
                continue;
            }

            var minutesValue = entry.Value.PropertyOrNull("window_minutes").Int64OrNull();
            var minutes = minutesValue is null ? null : checked((int?)minutesValue.Value);
            if (minutes is null)
            {
                continue;
            }

            var percent = entry.Value.PropertyOrNull("used_percent").DoubleOrNull();
            DateTimeOffset? resetsAt = null;
            var epoch = entry.Value.PropertyOrNull("resets_at").DoubleOrNull();
            if (epoch is not null)
            {
                resetsAt = DateTimeOffset.FromUnixTimeMilliseconds(checked((long)(epoch.Value * 1000d)));
            }
            else
            {
                var seconds = entry.Value.PropertyOrNull("resets_in_seconds").Int64OrNull();
                if (seconds is not null)
                {
                    resetsAt = _clock.UtcNow.AddSeconds(seconds.Value);
                }
            }

            var window = UsageWindow.FromUsedPercent(percent, resetsAt, minutes);
            if (window is null)
            {
                continue;
            }

            reading = IsShortWindow(minutes)
                ? reading with { ShortWindow = window }
                : reading with { WeeklyWindow = window };
        }

        return reading.ShortWindow is not null || reading.WeeklyWindow is not null;
    }

    private sealed record RateLimitReading(
        UsageWindow? ShortWindow,
        UsageWindow? WeeklyWindow,
        string? PlanType);
}
