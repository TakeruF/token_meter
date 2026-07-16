namespace TokenMeter.Core.Tests;

public sealed class ClaudeParserParityTests
{
    [Fact]
    public void Duplicate_message_request_pairs_match_shared_fixture()
    {
        var result = new ClaudeCodeLogParser().Parse(TestSupport.Lines("claude-session.jsonl"));
        Assert.Equal(60, result.Events.Count);
        Assert.Equal(33, result.Events.Select(item => item.Id).Distinct().Count());
        Assert.Equal(1_402_353, result.Events.GroupBy(item => item.Id).Sum(group => group.Last().TotalTokens));
        using var directory = new TempDirectory();
        using var store = new SqliteUsageStore(System.IO.Path.Combine(directory.Path, "history.sqlite"));
        Assert.Equal(33, store.InsertEvents(result.Events));
        Assert.Equal(0, store.InsertEvents(result.Events));
        Assert.Equal(1_402_353, store.GetEvents(UsageProviderId.ClaudeCode, DateTimeOffset.MinValue)
            .Sum(item => item.TotalTokens));
    }

    [Fact]
    public void Token_breakdown_matches_fixture_fields()
    {
        var item = Assert.Single(new ClaudeCodeLogParser().Parse([
            Line("m", "r", input: 2, cached: 11, creation: 7, output: 3),
        ]).Events);
        Assert.Equal(2, item.InputTokens);
        Assert.Equal(11, item.CachedInputTokens);
        Assert.Equal(7, item.CacheCreationTokens);
        Assert.Equal(3, item.OutputTokens);
        Assert.Equal(23, item.TotalTokens);
    }

    [Fact]
    public void Reasoning_is_null_not_zero() =>
        Assert.Null(Assert.Single(new ClaudeCodeLogParser().Parse([Line("m", "r")]).Events).ReasoningTokens);

    [Fact]
    public void Empty_file_returns_no_events()
    {
        var result = new ClaudeCodeLogParser().Parse([]);
        Assert.Empty(result.Events);
        Assert.Equal(0, result.MalformedLineCount);
    }

    [Fact]
    public void Unknown_fields_are_tolerated_and_synthetic_models_excluded()
    {
        var normal = Line("a", "r").Replace("\"message\":{", "\"future\":true,\"message\":{", StringComparison.Ordinal);
        var synthetic = Line("b", "r", model: "<synthetic>");
        var result = new ClaudeCodeLogParser().Parse([normal, synthetic]);
        Assert.Single(result.Events);
    }

    [Fact]
    public void Current_context_uses_latest_input_footprint()
    {
        var result = new ClaudeCodeLogParser().Parse([
            Line("a", "r", input: 1, cached: 2, creation: 3, timestamp: "2026-07-15T10:00:00Z"),
            Line("b", "r", input: 4, cached: 5, creation: 6, timestamp: "2026-07-15T11:00:00Z"),
        ]);
        Assert.Equal(15, result.LatestContextTokens);
    }

    private static string Line(
        string message,
        string request,
        long input = 1,
        long cached = 2,
        long creation = 3,
        long output = 4,
        string model = "claude",
        string timestamp = "2026-07-15T10:00:00Z") =>
        System.Text.Json.JsonSerializer.Serialize(new
        {
            type = "assistant",
            requestId = request,
            sessionId = "s",
            timestamp,
            message = new
            {
                id = message,
                model,
                usage = new
                {
                    input_tokens = input,
                    cache_read_input_tokens = cached,
                    cache_creation_input_tokens = creation,
                    output_tokens = output,
                },
            },
        });
}
