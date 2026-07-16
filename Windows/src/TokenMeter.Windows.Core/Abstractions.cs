namespace TokenMeter.Core;

public interface IClock
{
    DateTimeOffset UtcNow { get; }
}

public sealed class SystemClock : IClock
{
    public static SystemClock Instance { get; } = new();
    private SystemClock() { }
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}

public interface IPathResolver
{
    string UserProfile { get; }
    string ClaudeHome { get; }
    string ClaudeProjects { get; }
    string ClaudeCredentials { get; }
    string CodexHome { get; }
    string CodexSessions { get; }
    string CopilotHome { get; }
    string CopilotSessionState { get; }
    string AppDataRoot { get; }
    string DatabasePath { get; }
    IReadOnlyList<string> EnumerateJsonlFiles(string root, int? limit = null);
    IReadOnlyList<string> EnumerateCopilotEventFiles(int? limit = null);
}

public interface IUsageStore : IDisposable
{
    int InsertEvents(IEnumerable<UsageEvent> events);
    IReadOnlyList<UsageEvent> GetEvents(
        UsageProviderId? provider,
        DateTimeOffset since,
        DateTimeOffset? until = null);
    long GetCursor(string path);
    string? GetCursorFingerprint(string path);
    void SetCursor(string path, long offset, string? fingerprint = null);
    CumulativeTotals? GetSessionTotals(string sessionId);
    IReadOnlyList<string> GetSessionModels(UsageProviderId provider, string sessionPrefix);
    void SetSessionTotals(string sessionId, UsageProviderId provider, CumulativeTotals totals);
    void InsertLimitSample(
        UsageProviderId provider,
        DateTimeOffset timestamp,
        string kind,
        UsageWindow window,
        UsageSource source);
    LimitSample? GetLatestLimitSample(UsageProviderId provider, string kind);
    string? GetLatestModel(UsageProviderId provider);
    string? GetLatestModel(string sessionId);
    int PruneEvents(int days);
    void DeleteAllData();
    int EventCount();
}

public interface ICredentialProvider
{
    Task<ClaudeCredential> GetCredentialAsync(CancellationToken cancellationToken = default);
}

public interface IClaudeUsageClient
{
    Task<ClaudeUsageResponse> FetchAsync(
        string accessToken,
        CancellationToken cancellationToken = default);
}

public interface IUsageProvider : IAsyncDisposable
{
    UsageProviderId Id { get; }
    string DisplayName { get; }
    Task<ProviderAvailability> CheckAvailabilityAsync(CancellationToken cancellationToken = default);
    Task<UsageSnapshot> FetchCurrentUsageAsync(
        bool forceRefresh = false,
        CancellationToken cancellationToken = default);
    void StartMonitoring(Func<Task> onChange);
    void StopMonitoring();
}

public sealed class UsageProviderException : Exception
{
    public UsageProviderException(string message) : base(message) { }
    public UsageProviderException(string message, Exception innerException) : base(message, innerException) { }
}
