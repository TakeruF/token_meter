namespace TokenMeter.Core.Tests;

public sealed class AggregatorTests
{
    [Fact]
    public void Working_tokens_exclude_cached_input()
    {
        var item = TestSupport.Event(
            "a", UsageProviderId.Codex, DateTimeOffset.UtcNow,
            input: 10, cached: 1000, output: 20, reasoning: 5);

        Assert.Equal(35, item.WorkingTokens);
        Assert.Equal(1035, item.TotalTokens);
    }

    [Fact]
    public void Session_block_replays_five_hour_boundary()
    {
        var now = DateTimeOffset.Parse("2026-07-15T06:30:00Z");
        var events = new[]
        {
            TestSupport.Event("a", UsageProviderId.ClaudeCode, now.AddHours(-6), output: 10),
            TestSupport.Event("b", UsageProviderId.ClaudeCode, now.AddHours(-5), output: 20),
            TestSupport.Event("c", UsageProviderId.ClaudeCode, now.AddHours(-1), output: 30),
        };

        var result = new UsageAggregator(TimeZoneInfo.Utc).SessionBlock(
            events, UsageProviderId.ClaudeCode, now: now);

        Assert.NotNull(result);
        Assert.Equal(TokenWindowBoundary.Inferred, result.Boundary);
        Assert.Equal(30, result.Tokens);
    }

    [Fact]
    public void Reported_window_counts_only_inside_provider_boundary()
    {
        var reset = DateTimeOffset.Parse("2026-07-15T10:00:00Z");
        var events = new[]
        {
            TestSupport.Event("old", UsageProviderId.Codex, reset.AddHours(-6), output: 100),
            TestSupport.Event("new", UsageProviderId.Codex, reset.AddHours(-1), output: 20),
        };
        var window = new UsageWindow(.1, .9, reset, 300);

        var result = new UsageAggregator(TimeZoneInfo.Utc).ReportedWindowUsage(
            events, UsageProviderId.Codex, window);

        Assert.NotNull(result);
        Assert.Equal(20, result.Tokens);
        Assert.Equal(TokenWindowBoundary.Reported, result.Boundary);
    }

    [Fact]
    public void Recent_sessions_group_by_provider_and_session()
    {
        var now = DateTimeOffset.UtcNow;
        var events = new[]
        {
            TestSupport.Event("a", UsageProviderId.Codex, now, output: 1, model: "gpt", session: "same"),
            TestSupport.Event("b", UsageProviderId.Codex, now.AddMinutes(1), output: 2, model: "gpt", session: "same"),
            TestSupport.Event("c", UsageProviderId.ClaudeCode, now, output: 3, model: "claude", session: "same"),
        };

        var result = new UsageAggregator().RecentSessions(events);

        Assert.Equal(2, result.Count);
        Assert.Contains(result, item => item.Provider == UsageProviderId.Codex && item.Turns == 2);
    }
}
