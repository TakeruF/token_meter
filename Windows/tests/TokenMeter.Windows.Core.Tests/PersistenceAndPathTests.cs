namespace TokenMeter.Core.Tests;

public sealed class PersistenceAndPathTests
{
    [Fact]
    public void Store_deduplicates_events_and_persists_cursor()
    {
        var directory = Path.Combine(Path.GetTempPath(), "TokenMeterTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            using var store = new SqliteUsageStore(Path.Combine(directory, "history.sqlite"));
            var item = TestSupport.Event("same", UsageProviderId.Codex, DateTimeOffset.UtcNow, output: 10);

            Assert.Equal(1, store.InsertEvents([item, item]));
            store.SetCursor("file", 42);
            Assert.Equal(42, store.GetCursor("file"));
            Assert.Equal(1, store.EventCount());
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public void Path_resolver_honors_provider_environment_variables()
    {
        var root = Path.Combine(Path.GetTempPath(), "TokenMeterPaths");
        string? EnvironmentValue(string name) => name switch
        {
            "CLAUDE_CONFIG_DIR" => Path.Combine(root, "claude-custom"),
            "CODEX_HOME" => Path.Combine(root, "codex-custom"),
            "LOCALAPPDATA" => Path.Combine(root, "local"),
            _ => null,
        };
        var paths = new WindowsPathResolver(
            Path.Combine(root, "user"),
            environment: EnvironmentValue);

        Assert.EndsWith("claude-custom", paths.ClaudeHome, StringComparison.Ordinal);
        Assert.EndsWith("codex-custom", paths.CodexHome, StringComparison.Ordinal);
        Assert.EndsWith(Path.Combine("TokenMeter", "history.sqlite"), paths.DatabasePath, StringComparison.Ordinal);
    }

    [Fact]
    public void Jsonl_reader_leaves_partial_tail_unconsumed()
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "one\ntwo");
            var first = JsonlReader.ReadNewLines(path, 0);
            Assert.Equal(["one"], first.Lines);

            File.AppendAllText(path, "\n");
            var second = JsonlReader.ReadNewLines(path, first.NewOffset);
            Assert.Equal(["two"], second.Lines);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
