namespace TokenMeter.Core.Tests;

public sealed class CodexParserParityTests
{
    [Fact]
    public void Repeated_cumulative_value_emits_no_second_event()
    {
        var parser = new CodexLogParser();
        var result = parser.Parse([Count(100), Count(100, "2026-07-15T11:00:00Z")], "s");
        Assert.Single(result.Events);
    }

    [Fact]
    public void Previous_totals_prevent_resume_double_count()
    {
        var previous = new CumulativeTotals(100, 50, 10, 2, 110, 1);
        var result = new CodexLogParser().Parse([Count(150)], "s", previous);
        Assert.Equal(40, Assert.Single(result.Events).TotalTokens);
    }

    [Fact]
    public void Previous_model_is_kept_for_resumed_chunk()
    {
        var result = new CodexLogParser().Parse([Count(20)], "s", previousModel: "gpt-existing");
        Assert.Equal("gpt-existing", Assert.Single(result.Events).Model);
    }

    [Fact]
    public void Counter_restart_takes_current_value_whole()
    {
        var previous = new CumulativeTotals(1000, 500, 100, 10, 1100, 1);
        var result = new CodexLogParser().Parse([Count(55)], "s", previous);
        Assert.Equal(55, Assert.Single(result.Events).TotalTokens);
    }

    [Fact]
    public void Windows_are_classified_by_duration_not_slot()
    {
        var result = new CodexLogParser().Parse([Count(1, limits: Limits(10080, 300))], "s");
        Assert.Equal(300, result.ShortWindow!.WindowMinutes);
        Assert.Equal(10080, result.WeeklyWindow!.WindowMinutes);
    }

    [Fact]
    public void Weekly_window_in_primary_is_not_short()
    {
        var result = new CodexLogParser().Parse([Count(1, limits: Limits(10080, null))], "s");
        Assert.Null(result.ShortWindow);
        Assert.Equal(10080, result.WeeklyWindow!.WindowMinutes);
    }

    [Fact]
    public void Model_specific_limit_does_not_replace_general_limit()
    {
        var general = Count(1, limits: Limits(300, null));
        var model = Count(2, "2026-07-15T11:00:00Z", limits: Limits(10080, null, "codex-model"));
        var result = new CodexLogParser().Parse([general, model], "s");
        Assert.NotNull(result.ShortWindow);
        Assert.Null(result.WeeklyWindow);
    }

    [Fact]
    public void Model_specific_limit_alone_is_not_account_quota()
    {
        var result = new CodexLogParser().Parse([Count(1, limits: Limits(300, null, "codex-model"))], "s");
        Assert.Null(result.ShortWindow);
        Assert.Null(result.WeeklyWindow);
    }

    [Fact]
    public void Resets_at_is_unix_seconds()
    {
        var result = new CodexLogParser().Parse([Count(1, limits: Limits(300, null))], "s");
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_789_000_000), result.ShortWindow!.ResetsAt);
    }

    [Fact]
    public void Null_info_and_unknown_events_survive()
    {
        var unknown = "{\"type\":\"event_msg\",\"timestamp\":\"2026-07-15T10:00:00Z\",\"payload\":{\"type\":\"token_count\",\"info\":null}}";
        var result = new CodexLogParser().Parse([unknown, "{\"type\":\"future\"}"], "s");
        Assert.Empty(result.Events);
    }

    [Fact]
    public void Empty_input_yields_nothing() =>
        Assert.Empty(new CodexLogParser().Parse([], "s").Events);

    [Fact]
    public void Session_id_is_extracted_from_rollout_filename()
    {
        var id = CodexUsageProvider.SessionIdFromPath("C:\\x\\rollout-2026-07-15T10-00-00-12345678-1234-1234-1234-123456789abc.jsonl");
        Assert.Equal("12345678-1234-1234-1234-123456789abc", id);
    }

    private static string Count(long total, string timestamp = "2026-07-15T10:00:00Z", string? limits = null)
    {
        var input = Math.Max(0, total - 10);
        return System.Text.Json.JsonSerializer.Serialize(new
        {
            type = "event_msg",
            timestamp,
            payload = new
            {
                type = "token_count",
                info = new
                {
                    total_token_usage = new
                    {
                        input_tokens = input,
                        cached_input_tokens = 0,
                        output_tokens = 10,
                        reasoning_output_tokens = 0,
                        total_tokens = total,
                    },
                    last_token_usage = new { input_tokens = input },
                    model_context_window = 200000,
                },
                rate_limits = limits is null ? null : System.Text.Json.Nodes.JsonNode.Parse(limits),
            },
        });
    }

    private static string Limits(int primaryMinutes, int? secondaryMinutes, string id = "codex")
    {
        var secondary = secondaryMinutes is null
            ? "null"
            : $"{{\"used_percent\":20,\"window_minutes\":{secondaryMinutes},\"resets_at\":1789000000}}";
        return $"{{\"limit_id\":\"{id}\",\"plan_type\":\"pro\",\"primary\":{{\"used_percent\":10,\"window_minutes\":{primaryMinutes},\"resets_at\":1789000000}},\"secondary\":{secondary}}}";
    }
}
