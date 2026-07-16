namespace TokenMeter.Core.Tests;

public sealed class ReaderStoreProviderParityTests
{
    [Fact]
    public void Incremental_reader_returns_only_appended_lines()
    {
        var path = System.IO.Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "one\n");
            var first = JsonlReader.ReadNewLines(path, 0);
            File.AppendAllText(path, "two\n");
            var second = JsonlReader.ReadNewLines(path, first.NewOffset, first.PrefixFingerprint);
            Assert.Equal(["two"], second.Lines);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Partial_trailing_line_waits_for_next_pass()
    {
        var path = System.IO.Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "one\ntw");
            var first = JsonlReader.ReadNewLines(path, 0);
            File.AppendAllText(path, "o\n");
            var second = JsonlReader.ReadNewLines(path, first.NewOffset, first.PrefixFingerprint);
            Assert.Equal(["two"], second.Lines);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Truncated_file_restarts_from_zero()
    {
        var path = System.IO.Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "one\ntwo\n");
            var first = JsonlReader.ReadNewLines(path, 0);
            File.WriteAllText(path, "new\n");
            var second = JsonlReader.ReadNewLines(path, first.NewOffset, first.PrefixFingerprint);
            Assert.True(second.DidReset);
            Assert.Equal(["new"], second.Lines);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Replaced_file_with_same_length_is_detected()
    {
        var path = System.IO.Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "one\ntwo\n");
            var first = JsonlReader.ReadNewLines(path, 0);
            File.WriteAllText(path, "new\nlog\n");
            var second = JsonlReader.ReadNewLines(path, first.NewOffset, first.PrefixFingerprint);
            Assert.True(second.DidReset);
            Assert.Equal(["new", "log"], second.Lines);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Missing_file_throws_source_error()
    {
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), Guid.NewGuid() + ".jsonl");
        Assert.Throws<UsageProviderException>(() => JsonlReader.ReadNewLines(path, 0));
    }

    [Fact]
    public async Task Claude_reports_not_installed_without_home()
    {
        using var fixture = ProviderFixture();
        await using var provider = new ClaudeCodeUsageProvider(fixture.Paths, fixture.Store);
        Assert.Equal(ProviderAvailabilityKind.NotInstalled, (await provider.CheckAvailabilityAsync()).Kind);
    }

    [Fact]
    public async Task Codex_reports_no_data_for_empty_sessions()
    {
        using var fixture = ProviderFixture();
        Directory.CreateDirectory(fixture.Paths.CodexSessions);
        await using var provider = new CodexUsageProvider(fixture.Paths, fixture.Store);
        Assert.Equal(ProviderAvailabilityKind.NoData, (await provider.CheckAvailabilityAsync()).Kind);
    }

    [Fact]
    public async Task Copilot_reports_no_data_for_empty_session_state()
    {
        using var fixture = ProviderFixture();
        Directory.CreateDirectory(fixture.Paths.CopilotSessionState);
        await using var provider = new CopilotUsageProvider(fixture.Paths, fixture.Store);
        Assert.Equal(ProviderAvailabilityKind.NoData, (await provider.CheckAvailabilityAsync()).Kind);
    }

    [Fact]
    public void Limit_sample_round_trips()
    {
        using var fixture = ProviderFixture();
        var now = DateTimeOffset.UtcNow;
        fixture.Store.InsertLimitSample(UsageProviderId.Codex, now, "weekly", new UsageWindow(.2, .8, now.AddDays(1), 10080), UsageSource.LocalLog);
        var sample = fixture.Store.GetLatestLimitSample(UsageProviderId.Codex, "weekly")!;
        Assert.Equal(.8, sample.Window.RemainingRatio);
        Assert.Equal(10080, sample.Window.WindowMinutes);
    }

    [Fact]
    public void Delete_all_clears_events_cursors_and_totals()
    {
        using var fixture = ProviderFixture();
        fixture.Store.InsertEvents([TestSupport.Event("a", UsageProviderId.Codex, DateTimeOffset.UtcNow, output: 1)]);
        fixture.Store.SetCursor("file", 10, "hash");
        fixture.Store.SetSessionTotals("s", UsageProviderId.Codex, new CumulativeTotals(TotalTokens: 1));
        fixture.Store.DeleteAllData();
        Assert.Equal(0, fixture.Store.EventCount());
        Assert.Equal(0, fixture.Store.GetCursor("file"));
        Assert.Null(fixture.Store.GetSessionTotals("s"));
    }

    [Fact]
    public void Session_totals_round_trip()
    {
        using var fixture = ProviderFixture();
        var totals = new CumulativeTotals(1, 2, 3, 4, 5, 6);
        fixture.Store.SetSessionTotals("s", UsageProviderId.Codex, totals);
        Assert.Equal(totals, fixture.Store.GetSessionTotals("s"));
    }

    [Fact]
    public void Cursor_fingerprint_round_trips()
    {
        using var fixture = ProviderFixture();
        fixture.Store.SetCursor("file", 12, "ABC");
        Assert.Equal(12, fixture.Store.GetCursor("file"));
        Assert.Equal("ABC", fixture.Store.GetCursorFingerprint("file"));
    }

    [Fact]
    public void Enumerating_jsonl_files_sorts_newest_first()
    {
        using var fixture = ProviderFixture();
        Directory.CreateDirectory(fixture.Paths.ClaudeProjects);
        var old = System.IO.Path.Combine(fixture.Paths.ClaudeProjects, "old.jsonl");
        var newest = System.IO.Path.Combine(fixture.Paths.ClaudeProjects, "new.jsonl");
        File.WriteAllText(old, "\n");
        File.WriteAllText(newest, "\n");
        File.SetLastWriteTimeUtc(old, DateTime.UtcNow.AddMinutes(-2));
        File.SetLastWriteTimeUtc(newest, DateTime.UtcNow);
        Assert.Equal(newest, fixture.Paths.EnumerateJsonlFiles(fixture.Paths.ClaudeProjects).First());
    }

    private static ProviderFixtureHolder ProviderFixture()
    {
        var directory = new TempDirectory();
        var paths = new WindowsPathResolver(
            System.IO.Path.Combine(directory.Path, "user"),
            System.IO.Path.Combine(directory.Path, "app"),
            _ => null);
        var store = new SqliteUsageStore(paths.DatabasePath);
        return new ProviderFixtureHolder(directory, paths, store);
    }

    private sealed class ProviderFixtureHolder(
        TempDirectory directory,
        WindowsPathResolver paths,
        SqliteUsageStore store) : IDisposable
    {
        public WindowsPathResolver Paths { get; } = paths;
        public SqliteUsageStore Store { get; } = store;
        public void Dispose()
        {
            Store.Dispose();
            directory.Dispose();
        }
    }
}
