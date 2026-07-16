using System.Text.Json.Serialization;

namespace TokenMeter.Core;

[JsonConverter(typeof(JsonStringEnumConverter<UsageProviderId>))]
public enum UsageProviderId
{
    ClaudeCode,
    Codex,
    CopilotCli,
}

public static class UsageProviderIdExtensions
{
    public static string DisplayName(this UsageProviderId provider) => provider switch
    {
        UsageProviderId.ClaudeCode => "Claude",
        UsageProviderId.Codex => "Codex",
        UsageProviderId.CopilotCli => "Copilot",
        _ => provider.ToString(),
    };

    public static string StorageValue(this UsageProviderId provider) => provider switch
    {
        UsageProviderId.ClaudeCode => "claudeCode",
        UsageProviderId.Codex => "codex",
        UsageProviderId.CopilotCli => "copilotCli",
        _ => throw new ArgumentOutOfRangeException(nameof(provider)),
    };

    public static bool TryParseStorageValue(string value, out UsageProviderId provider)
    {
        provider = value switch
        {
            "claudeCode" => UsageProviderId.ClaudeCode,
            "codex" => UsageProviderId.Codex,
            "copilotCli" => UsageProviderId.CopilotCli,
            _ => default,
        };
        return value is "claudeCode" or "codex" or "copilotCli";
    }
}

[JsonConverter(typeof(JsonStringEnumConverter<UsageSource>))]
public enum UsageSource
{
    Command,
    LocalLog,
    LocalServer,
    StatusLine,
    OfficialApi,
}

public static class UsageSourceExtensions
{
    public static string StorageValue(this UsageSource source) => source switch
    {
        UsageSource.Command => "command",
        UsageSource.LocalLog => "localLog",
        UsageSource.LocalServer => "localServer",
        UsageSource.StatusLine => "statusLine",
        UsageSource.OfficialApi => "officialAPI",
        _ => throw new ArgumentOutOfRangeException(nameof(source)),
    };

    public static bool TryParseStorageValue(string value, out UsageSource source)
    {
        source = value switch
        {
            "command" => UsageSource.Command,
            "localLog" => UsageSource.LocalLog,
            "localServer" => UsageSource.LocalServer,
            "statusLine" => UsageSource.StatusLine,
            "officialAPI" => UsageSource.OfficialApi,
            _ => default,
        };
        return value is "command" or "localLog" or "localServer" or "statusLine" or "officialAPI";
    }
}

public sealed record UsageWindow(
    double? UsedRatio,
    double? RemainingRatio,
    DateTimeOffset? ResetsAt,
    int? WindowMinutes = null)
{
    public static UsageWindow? FromUsedPercent(
        double? percent,
        DateTimeOffset? resetsAt,
        int? windowMinutes)
    {
        if (percent is null)
        {
            return null;
        }

        var used = Math.Clamp(percent.Value / 100d, 0d, 1d);
        return new UsageWindow(used, 1d - used, resetsAt, windowMinutes);
    }
}

[JsonConverter(typeof(JsonStringEnumConverter<ClaudeUsageError>))]
public enum ClaudeUsageError
{
    CredentialsNotFound,
    CredentialAccessDenied,
    InvalidCredentials,
    SessionExpired,
    Unauthorized,
    Forbidden,
    RateLimited,
    ServerError,
    NetworkUnavailable,
    InvalidResponse,
    RequestFailed,
}

[JsonConverter(typeof(JsonStringEnumConverter<TokenWindowBoundary>))]
public enum TokenWindowBoundary
{
    Reported,
    Inferred,
    Rolling,
}

public sealed record TokenWindowUsage(
    DateTimeOffset Start,
    DateTimeOffset? ResetsAt,
    long Tokens,
    TokenWindowBoundary Boundary,
    int? WindowMinutes = null)
{
    [JsonIgnore]
    public bool IsBoundaryInferred => Boundary == TokenWindowBoundary.Inferred;
}

public sealed record UsageSnapshot(
    Guid Id,
    UsageProviderId Provider,
    DateTimeOffset Timestamp,
    string? ModelName,
    long? InputTokens,
    long? CachedInputTokens,
    long? CacheCreationTokens,
    long? OutputTokens,
    long? ReasoningTokens,
    long? TotalTokens,
    long? CurrentContextTokens,
    long? ContextWindowTokens,
    UsageWindow? ShortWindow,
    UsageWindow? WeeklyWindow,
    UsageWindow? SonnetWeeklyWindow,
    DateTimeOffset? QuotaUpdatedAt,
    bool QuotaIsCached,
    ClaudeUsageError? QuotaError,
    bool QuotaIntegrationEnabled,
    TokenWindowUsage? ShortWindowUsage,
    TokenWindowUsage? WeeklyWindowUsage,
    string? PlanType,
    UsageSource Source)
{
    public static UsageSnapshot Create(
        UsageProviderId provider,
        DateTimeOffset timestamp,
        UsageSource source,
        string? modelName = null,
        long? inputTokens = null,
        long? cachedInputTokens = null,
        long? cacheCreationTokens = null,
        long? outputTokens = null,
        long? reasoningTokens = null,
        long? totalTokens = null,
        long? currentContextTokens = null,
        long? contextWindowTokens = null,
        UsageWindow? shortWindow = null,
        UsageWindow? weeklyWindow = null,
        UsageWindow? sonnetWeeklyWindow = null,
        DateTimeOffset? quotaUpdatedAt = null,
        bool quotaIsCached = false,
        ClaudeUsageError? quotaError = null,
        bool quotaIntegrationEnabled = false,
        TokenWindowUsage? shortWindowUsage = null,
        TokenWindowUsage? weeklyWindowUsage = null,
        string? planType = null) => new(
            Guid.NewGuid(), provider, timestamp, modelName, inputTokens, cachedInputTokens,
            cacheCreationTokens, outputTokens, reasoningTokens, totalTokens,
            currentContextTokens, contextWindowTokens, shortWindow, weeklyWindow,
            sonnetWeeklyWindow, quotaUpdatedAt, quotaIsCached, quotaError,
            quotaIntegrationEnabled, shortWindowUsage, weeklyWindowUsage, planType, source);

    [JsonIgnore]
    public UsageWindow? PrimaryWindow =>
        new[] { ShortWindow, WeeklyWindow, SonnetWeeklyWindow }
            .Where(window => window is not null)
            .MinBy(window => window!.RemainingRatio ?? 1d);

    [JsonIgnore]
    public bool HasQuotaInformation =>
        ShortWindow is not null || WeeklyWindow is not null || SonnetWeeklyWindow is not null;
}

public sealed record UsageEvent(
    string Id,
    UsageProviderId Provider,
    DateTimeOffset Timestamp,
    string? Model,
    string? SessionId,
    long InputTokens,
    long CachedInputTokens,
    long CacheCreationTokens,
    long OutputTokens,
    long? ReasoningTokens,
    long TotalTokens,
    UsageSource Source)
{
    [JsonIgnore]
    public long WorkingTokens => TotalTokens - CachedInputTokens;
}

public sealed record DailyUsage(
    DateTimeOffset Day,
    UsageProviderId Provider,
    long InputTokens,
    long CachedInputTokens,
    long CacheCreationTokens,
    long OutputTokens,
    long? ReasoningTokens,
    long TotalTokens)
{
    [JsonIgnore]
    public long WorkingTokens => TotalTokens - CachedInputTokens;
}

public sealed record SessionSummary(
    string Id,
    UsageProviderId Provider,
    DateTimeOffset Start,
    DateTimeOffset End,
    int Turns,
    string? Model,
    long InputTokens,
    long CachedInputTokens,
    long CacheCreationTokens,
    long OutputTokens,
    long? ReasoningTokens,
    long TotalTokens)
{
    [JsonIgnore]
    public long WorkingTokens => TotalTokens - CachedInputTokens;
}

public sealed record ModelUsage(string Model, UsageProviderId Provider, long TotalTokens);

public sealed record CumulativeTotals(
    long InputTokens = 0,
    long CachedInputTokens = 0,
    long OutputTokens = 0,
    long ReasoningTokens = 0,
    long TotalTokens = 0,
    long EventCount = 0);

public enum ProviderAvailabilityKind
{
    Available,
    NotInstalled,
    NotLoggedIn,
    NoData,
    PermissionDenied,
}

public sealed record ProviderAvailability(
    ProviderAvailabilityKind Kind,
    string Detail,
    bool HasQuota = false);

public sealed record LimitSample(UsageWindow Window, DateTimeOffset Timestamp, UsageSource Source);
