namespace TokenMeter.Core.Tests;

public sealed class AggregationParityTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-07-15T05:00:00Z");

    [Fact]
    public void Day_buckets_follow_user_timezone()
    {
        var item = TestSupport.Event("a", UsageProviderId.ClaudeCode, DateTimeOffset.Parse("2026-07-14T23:30:00Z"), output: 100);
        var tokyo = new UsageAggregator(TimeZoneInfo.FindSystemTimeZoneById(
            OperatingSystem.IsWindows() ? "Tokyo Standard Time" : "Asia/Tokyo"));
        var utc = new UsageAggregator(TimeZoneInfo.Utc);
        Assert.Equal(15, tokyo.DailyUsage([item], UsageProviderId.ClaudeCode, 7, Now).Single().Day.Day);
        Assert.Equal(14, utc.DailyUsage([item], UsageProviderId.ClaudeCode, 7, Now).Single().Day.Day);
    }

    [Fact]
    public void Today_excludes_before_local_midnight()
    {
        var aggregator = new UsageAggregator(TimeZoneInfo.Utc);
        var items = new[]
        {
            TestSupport.Event("old", UsageProviderId.ClaudeCode, Now.AddDays(-1), output: 500),
            TestSupport.Event("new", UsageProviderId.ClaudeCode, Now.AddHours(-1), output: 70),
        };
        Assert.Equal(70, aggregator.TodayTotals(items, UsageProviderId.ClaudeCode, Now)!.TotalTokens);
    }

    [Fact]
    public void Series_zero_fills_and_keeps_reasoning_null()
    {
        var series = new UsageAggregator(TimeZoneInfo.Utc).DailySeries(
            [TestSupport.Event("a", UsageProviderId.ClaudeCode, Now, output: 10)],
            UsageProviderId.ClaudeCode,
            7,
            Now);
        Assert.Equal(7, series.Count);
        Assert.Equal(10, series.Sum(item => item.TotalTokens));
        Assert.All(series, item => Assert.Null(item.ReasoningTokens));
    }

    [Fact]
    public void Reasoning_is_summed_when_reported()
    {
        var events = new[]
        {
            TestSupport.Event("a", UsageProviderId.Codex, Now, output: 10, reasoning: 4),
            TestSupport.Event("b", UsageProviderId.Codex, Now, output: 20, reasoning: 6),
        };
        Assert.Equal(10, new UsageAggregator(TimeZoneInfo.Utc)
            .TodayTotals(events, UsageProviderId.Codex, Now)!.ReasoningTokens);
    }

    [Fact]
    public void Model_breakdown_groups_and_sorts()
    {
        var events = new[]
        {
            TestSupport.Event("a", UsageProviderId.ClaudeCode, Now, output: 100, model: "opus"),
            TestSupport.Event("b", UsageProviderId.ClaudeCode, Now, output: 300, model: "sonnet"),
            TestSupport.Event("c", UsageProviderId.ClaudeCode, Now, output: 50, model: "opus"),
        };
        var result = new UsageAggregator().ModelBreakdown(events);
        Assert.Equal(["sonnet", "opus"], result.Select(item => item.Model));
        Assert.Equal([300L, 150L], result.Select(item => item.TotalTokens));
    }

    [Fact]
    public void Retention_prunes_old_events_only()
    {
        using var directory = new TempDirectory();
        using var store = new SqliteUsageStore(System.IO.Path.Combine(directory.Path, "db.sqlite"));
        store.InsertEvents([
            TestSupport.Event("old", UsageProviderId.Codex, DateTimeOffset.Now.AddDays(-40), output: 1),
            TestSupport.Event("new", UsageProviderId.Codex, DateTimeOffset.Now.AddDays(-2), output: 1),
        ]);
        Assert.Equal(1, store.PruneEvents(30));
        Assert.Equal("new", Assert.Single(store.GetEvents(null, DateTimeOffset.MinValue)).Id);
    }

    [Theory]
    [InlineData(1_840_230, "1.84M")]
    [InlineData(12_500, "12.5K")]
    [InlineData(842, "842")]
    public void Token_abbreviation_is_metric(long tokens, string expected) =>
        Assert.Equal(expected, UsageAggregator.AbbreviateTokens(tokens));

    [Fact]
    public void Sessions_separate_work_from_cache()
    {
        var events = new[]
        {
            TestSupport.Event("a1", UsageProviderId.ClaudeCode, Now, cached: 100_000, output: 500, session: "A"),
            TestSupport.Event("a2", UsageProviderId.ClaudeCode, Now.AddMinutes(5), input: 40, cached: 101_000, output: 700, session: "A"),
        };
        var session = Assert.Single(new UsageAggregator().RecentSessions(events));
        Assert.Equal(1_240, session.WorkingTokens);
        Assert.Equal(201_000, session.CachedInputTokens);
    }

    [Fact]
    public void Codex_work_does_not_double_count_reasoning()
    {
        var item = TestSupport.Event("c", UsageProviderId.Codex, Now, input: 10, cached: 8, output: 5, reasoning: 2, total: 15);
        Assert.Equal(7, item.WorkingTokens);
    }

    [Fact]
    public void Copilot_work_excludes_cached_input()
    {
        var item = TestSupport.Event("g", UsageProviderId.CopilotCli, Now, input: 10, cached: 6, cacheCreation: 3, output: 4, total: 14);
        Assert.Equal(8, item.WorkingTokens);
    }

    [Fact]
    public void Claude_work_keeps_cache_creation()
    {
        var item = TestSupport.Event("a", UsageProviderId.ClaudeCode, Now, input: 40, cached: 201_000, cacheCreation: 900, output: 700);
        Assert.Equal(1_640, item.WorkingTokens);
    }

    [Fact]
    public void Events_without_session_id_stay_distinct()
    {
        var events = new[]
        {
            TestSupport.Event("x", UsageProviderId.ClaudeCode, Now, output: 1),
            TestSupport.Event("y", UsageProviderId.ClaudeCode, Now.AddMinutes(1), output: 1),
        };
        Assert.Equal(2, new UsageAggregator().RecentSessions(events).Count);
    }

    [Fact]
    public void Hourly_series_stops_at_current_hour()
    {
        var now = DateTimeOffset.Parse("2026-07-15T12:30:00Z");
        var events = new[]
        {
            TestSupport.Event("a", UsageProviderId.ClaudeCode, new DateTimeOffset(2026, 7, 15, 9, 0, 0, TimeSpan.Zero), output: 100),
            TestSupport.Event("b", UsageProviderId.ClaudeCode, new DateTimeOffset(2026, 7, 15, 12, 0, 0, TimeSpan.Zero), output: 50),
        };
        var series = new UsageAggregator(TimeZoneInfo.Utc).HourlySeries(events, UsageProviderId.ClaudeCode, now);
        Assert.Equal(13, series.Count);
        Assert.Equal(100, series[9].TotalTokens);
        Assert.Equal(0, series[10].TotalTokens);
    }

    [Fact]
    public void Total_tokens_sums_provider_values() =>
        Assert.Equal(3, new UsageAggregator().TotalTokens([
            TestSupport.Event("a", UsageProviderId.Codex, Now, output: 1),
            TestSupport.Event("b", UsageProviderId.Codex, Now, output: 2),
        ]));
}
