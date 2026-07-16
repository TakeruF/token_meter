namespace TokenMeter.Core.Tests;

public sealed class CopilotParserParityTests
{
    [Fact]
    public void Cumulative_shutdowns_emit_deltas()
    {
        var parser = new CopilotLogParser();
        var first = parser.Parse([Line(100, 10)], "s");
        var second = parser.Parse([Line(300, 40)], "s", first.TotalsByModel);
        var item = Assert.Single(second.Events);
        Assert.Equal(200, item.InputTokens);
        Assert.Equal(30, item.OutputTokens);
        Assert.Equal(230, item.TotalTokens);
    }

    [Fact]
    public void Counter_restart_uses_current_value()
    {
        var previous = new Dictionary<string, CumulativeTotals>
        {
            ["model"] = new(1000, 0, 100, 0, 1100, 1),
        };
        Assert.Equal(55, Assert.Single(new CopilotLogParser().Parse([Line(50, 5)], "s", previous).Events).TotalTokens);
    }

    [Fact]
    public void Non_shutdown_lines_are_ignored() =>
        Assert.Empty(new CopilotLogParser().Parse(["{\"type\":\"assistant.message\"}"], "s").Events);

    [Fact]
    public void Zero_delta_produces_no_event() =>
        Assert.Empty(new CopilotLogParser().Parse([Line(0, 0)], "s").Events);

    private static string Line(long input, long output) =>
        System.Text.Json.JsonSerializer.Serialize(new
        {
            type = "session.shutdown",
            timestamp = "2026-07-15T10:00:00Z",
            data = new
            {
                modelMetrics = new Dictionary<string, object>
                {
                    ["model"] = new
                    {
                        usage = new
                        {
                            inputTokens = input,
                            outputTokens = output,
                            cacheReadTokens = 0,
                            cacheWriteTokens = 0,
                        },
                    },
                },
            },
        });
}
