namespace TokenMeter.Core.Tests;

internal sealed class FixedClock(DateTimeOffset now) : IClock
{
    public DateTimeOffset UtcNow { get; set; } = now;
}

internal static class TestSupport
{
    public static string Fixture(string name) =>
        Path.Combine(AppContext.BaseDirectory, "Fixtures", name);

    public static IReadOnlyList<string> Lines(string name) => File.ReadAllLines(Fixture(name));

    public static UsageEvent Event(
        string id,
        UsageProviderId provider,
        DateTimeOffset timestamp,
        long input = 0,
        long cached = 0,
        long cacheCreation = 0,
        long output = 0,
        long? reasoning = null,
        string? model = null,
        string? session = null,
        long? total = null) => new(
            id,
            provider,
            timestamp,
            model,
            session,
            input,
            cached,
            cacheCreation,
            output,
            reasoning,
            total ?? input + cached + cacheCreation + output + (reasoning ?? 0),
            UsageSource.LocalLog);
}

internal sealed class TempDirectory : IDisposable
{
    public TempDirectory()
    {
        Path = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "TokenMeterTests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, true);
        }
    }
}
