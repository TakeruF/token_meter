using System.Text.Json;

namespace TokenMeter.Core;

public sealed record CopilotParseResult(
    IReadOnlyList<UsageEvent> Events,
    IReadOnlyDictionary<string, CumulativeTotals> TotalsByModel,
    string? LatestModel,
    DateTimeOffset? LatestTimestamp,
    int MalformedLineCount,
    int CandidateLineCount,
    int TotalLineCount);

public sealed class CopilotLogParser
{
    public CopilotParseResult Parse(
        IReadOnlyList<string> lines,
        string sessionId,
        IReadOnlyDictionary<string, CumulativeTotals>? previousTotalsByModel = null)
    {
        var totalsByModel = previousTotalsByModel is null
            ? new Dictionary<string, CumulativeTotals>()
            : new Dictionary<string, CumulativeTotals>(previousTotalsByModel);
        var events = new List<UsageEvent>();
        string? latestModel = null;
        DateTimeOffset? latestTimestamp = null;
        var malformed = 0;
        var candidates = 0;

        foreach (var sourceLine in lines)
        {
            var line = sourceLine.Trim();
            if (line.Length == 0 || !line.Contains("session.shutdown", StringComparison.Ordinal))
            {
                continue;
            }

            candidates++;
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                var payload = root.PropertyOrNull("data");
                var metrics = payload?.PropertyOrNull("modelMetrics");
                var timestamp = LogDate.Parse(root.PropertyOrNull("timestamp").StringOrNull());
                if (root.PropertyOrNull("type").StringOrNull() != "session.shutdown" ||
                    metrics is not { ValueKind: JsonValueKind.Object } || timestamp is null)
                {
                    continue;
                }

                foreach (var modelEntry in metrics.Value.EnumerateObject())
                {
                    var usage = modelEntry.Value.PropertyOrNull("usage");
                    if (usage is null)
                    {
                        continue;
                    }

                    var model = modelEntry.Name;
                    var currentInput = usage.Value.PropertyOrNull("inputTokens").Int64OrNull() ?? 0;
                    var currentCacheRead = usage.Value.PropertyOrNull("cacheReadTokens").Int64OrNull() ?? 0;
                    var currentCacheWrite = usage.Value.PropertyOrNull("cacheWriteTokens").Int64OrNull() ?? 0;
                    var currentOutput = usage.Value.PropertyOrNull("outputTokens").Int64OrNull() ?? 0;
                    var currentTotal = currentInput + currentOutput;
                    var previous = totalsByModel.GetValueOrDefault(model) ?? new CumulativeTotals();
                    var restarted = currentTotal < previous.TotalTokens;
                    var deltaInput = restarted ? currentInput : currentInput - previous.InputTokens;
                    var deltaCacheRead = restarted ? currentCacheRead : currentCacheRead - previous.CachedInputTokens;
                    var deltaCacheWrite = restarted ? currentCacheWrite : currentCacheWrite - previous.ReasoningTokens;
                    var deltaOutput = restarted ? currentOutput : currentOutput - previous.OutputTokens;
                    var deltaTotal = restarted ? currentTotal : currentTotal - previous.TotalTokens;

                    var totals = new CumulativeTotals(
                        currentInput,
                        currentCacheRead,
                        currentOutput,
                        currentCacheWrite,
                        currentTotal,
                        previous.EventCount + 1);
                    totalsByModel[model] = totals;
                    latestTimestamp = timestamp;
                    latestModel = model;

                    if (deltaTotal <= 0)
                    {
                        continue;
                    }

                    events.Add(new UsageEvent(
                        $"{sessionId}|{model}|{timestamp.Value.ToUnixTimeMilliseconds()}|{totals.EventCount}",
                        UsageProviderId.CopilotCli,
                        timestamp.Value,
                        model,
                        sessionId,
                        Math.Max(0, deltaInput),
                        Math.Max(0, deltaCacheRead),
                        Math.Max(0, deltaCacheWrite),
                        Math.Max(0, deltaOutput),
                        null,
                        deltaTotal,
                        UsageSource.LocalLog));
                }
            }
            catch (JsonException)
            {
                malformed++;
            }
        }

        return new CopilotParseResult(
            events,
            totalsByModel,
            latestModel,
            latestTimestamp,
            malformed,
            candidates,
            lines.Count);
    }
}
