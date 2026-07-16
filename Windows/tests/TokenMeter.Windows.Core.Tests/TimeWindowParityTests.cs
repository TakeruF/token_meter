namespace TokenMeter.Core.Tests;

public sealed class TimeWindowParityTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-07-15T12:00:00Z");
    private readonly UsageAggregator _aggregator = new(TimeZoneInfo.Utc);

    [Fact]
    public void Session_block_counts_only_still_open_block()
    {
        var result = _aggregator.SessionBlock([
            Event("old", Now.AddHours(-7), 100),
            Event("current", Now.AddHours(-2), 30),
        ], UsageProviderId.ClaudeCode, now: Now)!;
        Assert.Equal(30, result.Tokens);
        Assert.Equal(Now.AddHours(-2), result.Start);
    }

    [Fact]
    public void Session_block_is_null_after_lapse()
    {
        Assert.Null(_aggregator.SessionBlock([Event("old", Now.AddHours(-6), 1)], UsageProviderId.ClaudeCode, now: Now));
    }

    [Fact]
    public void Session_block_ignores_other_providers()
    {
        Assert.Null(_aggregator.SessionBlock([TestSupport.Event("c", UsageProviderId.Codex, Now, output: 1)], UsageProviderId.ClaudeCode, now: Now));
    }

    [Fact]
    public void Session_block_is_null_without_events() =>
        Assert.Null(_aggregator.SessionBlock([], UsageProviderId.ClaudeCode, now: Now));

    [Fact]
    public void Reported_window_derives_start_from_duration()
    {
        var reset = Now.AddHours(1);
        var result = _aggregator.ReportedWindowUsage(
            [TestSupport.Event("a", UsageProviderId.Codex, Now, output: 10)],
            UsageProviderId.Codex,
            new UsageWindow(.2, .8, reset, 300))!;
        Assert.Equal(reset.AddMinutes(-300), result.Start);
        Assert.Equal(reset, result.ResetsAt);
    }

    [Fact]
    public void Reported_window_requires_duration()
    {
        Assert.Null(_aggregator.ReportedWindowUsage([], UsageProviderId.Codex, new UsageWindow(.2, .8, Now, null)));
    }

    [Fact]
    public void Rolling_window_has_no_reset()
    {
        var result = _aggregator.RollingWindowUsage([Event("a", Now, 1)], UsageProviderId.ClaudeCode, 7, Now)!;
        Assert.Null(result.ResetsAt);
        Assert.Equal(TokenWindowBoundary.Rolling, result.Boundary);
    }

    [Fact]
    public void Rolling_window_is_null_when_empty() =>
        Assert.Null(_aggregator.RollingWindowUsage([], UsageProviderId.ClaudeCode, 7, Now));

    [Fact]
    public void Used_percent_builds_complementary_ratios()
    {
        var window = UsageWindow.FromUsedPercent(25, Now, 300)!;
        Assert.Equal(.25, window.UsedRatio);
        Assert.Equal(.75, window.RemainingRatio);
    }

    private static UsageEvent Event(string id, DateTimeOffset time, long output) =>
        TestSupport.Event(id, UsageProviderId.ClaudeCode, time, output: output);
}
