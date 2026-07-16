namespace TokenMeter.Core.Tests;

public sealed class ParserTests
{
    [Fact]
    public void Claude_fixture_matches_expected_usage()
    {
        var result = new ClaudeCodeLogParser().Parse(TestSupport.Lines("claude-session.jsonl"));

        Assert.Equal(60, result.TotalLineCount);
        Assert.Equal(60, result.Events.Count);
        Assert.Equal(33, result.Events.Select(item => item.Id).Distinct().Count());
        Assert.Equal(2_503_906, result.Events.Sum(item => item.TotalTokens));
        Assert.Equal(1_402_353, result.Events.GroupBy(item => item.Id).Sum(group => group.Last().TotalTokens));
        Assert.All(result.Events, item => Assert.Equal(UsageProviderId.ClaudeCode, item.Provider));
        Assert.True(result.Events.Select(item => item.Id).Distinct().Count() > 0);
        Assert.True(result.Events.Sum(item => item.TotalTokens) > 0);
    }

    [Fact]
    public void Claude_drops_broken_json_without_losing_valid_records()
    {
        var result = new ClaudeCodeLogParser().Parse(TestSupport.Lines("claude-broken.jsonl"));

        Assert.True(result.MalformedLineCount > 0);
        Assert.Equal(2, result.Events.Count);
        Assert.Equal(3, result.CandidateLineCount);
        Assert.Equal(1, result.MalformedLineCount);
    }

    [Fact]
    public void Codex_fixture_produces_deltas_and_quota_windows()
    {
        var result = new CodexLogParser().Parse(
            TestSupport.Lines("codex-session.jsonl"),
            "test-session");

        Assert.NotEmpty(result.Events);
        Assert.Equal(44_920_896, result.Events.Sum(item => item.TotalTokens));
        Assert.Equal(44_920_896, result.Totals.TotalTokens);
        Assert.True(result.ShortWindow is not null || result.WeeklyWindow is not null);
        Assert.All(result.Events, item => Assert.Equal(UsageProviderId.Codex, item.Provider));
        Assert.Equal("gpt-5.6-sol", result.LatestModel);
        Assert.Equal(258_400, result.ContextWindowTokens);
    }

    [Fact]
    public void Codex_partial_fixture_does_not_throw()
    {
        var result = new CodexLogParser().Parse(
            TestSupport.Lines("codex-partial.jsonl"),
            "partial");

        Assert.True(result.TotalLineCount > 0);
    }

    [Fact]
    public void Copilot_parser_reads_shutdown_totals()
    {
        var lines = new[]
        {
            "{\"type\":\"session.shutdown\",\"timestamp\":\"2026-07-15T12:00:00Z\",\"data\":{\"modelMetrics\":{\"gpt-5\":{\"usage\":{\"inputTokens\":100,\"outputTokens\":20,\"cacheReadTokens\":80,\"cacheWriteTokens\":5}}}}}",
        };

        var result = new CopilotLogParser().Parse(lines, "session");

        var item = Assert.Single(result.Events);
        Assert.Equal(120, item.TotalTokens);
        Assert.Equal(80, item.CachedInputTokens);
        Assert.Equal(5, item.CacheCreationTokens);
    }
}
