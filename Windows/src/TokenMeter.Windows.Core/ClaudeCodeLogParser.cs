using System.Text.Json;

namespace TokenMeter.Core;

public sealed record ClaudeParseResult(
    IReadOnlyList<UsageEvent> Events,
    string? LatestModel,
    long? LatestContextTokens,
    DateTimeOffset? LatestTimestamp,
    int MalformedLineCount,
    int CandidateLineCount,
    int TotalLineCount);

public sealed class ClaudeCodeLogParser
{
    private static readonly HashSet<string> SyntheticModels = ["<synthetic>"];

    public ClaudeParseResult Parse(IReadOnlyList<string> lines, string? sessionId = null)
    {
        var events = new List<UsageEvent>();
        string? latestModel = null;
        long? latestContext = null;
        DateTimeOffset? latestTimestamp = null;
        var malformed = 0;
        var candidates = 0;

        foreach (var sourceLine in lines)
        {
            var line = sourceLine.Trim();
            if (line.Length == 0 || !line.Contains("\"usage\"", StringComparison.Ordinal))
            {
                continue;
            }

            candidates++;
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.PropertyOrNull("type").StringOrNull() != "assistant")
                {
                    continue;
                }

                var message = root.PropertyOrNull("message");
                var usage = message?.PropertyOrNull("usage");
                if (message is null || usage is null)
                {
                    continue;
                }

                var model = message.Value.PropertyOrNull("model").StringOrNull();
                if (model is not null && SyntheticModels.Contains(model))
                {
                    continue;
                }

                var messageId = message.Value.PropertyOrNull("id").StringOrNull();
                if (string.IsNullOrEmpty(messageId))
                {
                    continue;
                }

                var timestamp = LogDate.Parse(root.PropertyOrNull("timestamp").StringOrNull());
                if (timestamp is null)
                {
                    continue;
                }

                var input = usage.Value.PropertyOrNull("input_tokens").Int64OrNull() ?? 0;
                var cacheRead = usage.Value.PropertyOrNull("cache_read_input_tokens").Int64OrNull() ?? 0;
                var cacheCreation = usage.Value.PropertyOrNull("cache_creation_input_tokens").Int64OrNull() ?? 0;
                var output = usage.Value.PropertyOrNull("output_tokens").Int64OrNull() ?? 0;
                var total = input + cacheRead + cacheCreation + output;
                if (total <= 0)
                {
                    continue;
                }

                var requestId = root.PropertyOrNull("requestId").StringOrNull() ?? string.Empty;
                var eventId = $"{messageId}|{requestId}";
                events.Add(new UsageEvent(
                    eventId,
                    UsageProviderId.ClaudeCode,
                    timestamp.Value,
                    model,
                    root.PropertyOrNull("sessionId").StringOrNull() ?? sessionId,
                    input,
                    cacheRead,
                    cacheCreation,
                    output,
                    null,
                    total,
                    UsageSource.LocalLog));

                if (latestTimestamp is null || timestamp >= latestTimestamp)
                {
                    latestTimestamp = timestamp;
                    latestModel = model;
                    latestContext = input + cacheRead + cacheCreation;
                }
            }
            catch (JsonException)
            {
                malformed++;
            }
        }

        return new ClaudeParseResult(
            events,
            latestModel,
            latestContext,
            latestTimestamp,
            malformed,
            candidates,
            lines.Count);
    }
}
