namespace TokenMeter.Core;

public abstract class UsageProviderBase : IUsageProvider
{
    private DebouncedDirectoryWatcher? _watcher;

    public abstract UsageProviderId Id { get; }
    public string DisplayName => Id.DisplayName();
    protected abstract IReadOnlyList<string> WatchPaths { get; }

    public abstract Task<ProviderAvailability> CheckAvailabilityAsync(
        CancellationToken cancellationToken = default);

    public abstract Task<UsageSnapshot> FetchCurrentUsageAsync(
        bool forceRefresh = false,
        CancellationToken cancellationToken = default);

    public void StartMonitoring(Func<Task> onChange)
    {
        if (_watcher is not null)
        {
            return;
        }
        _watcher = new DebouncedDirectoryWatcher(WatchPaths);
        _watcher.Start(onChange);
    }

    public void StopMonitoring()
    {
        _watcher?.Dispose();
        _watcher = null;
    }

    public ValueTask DisposeAsync()
    {
        StopMonitoring();
        GC.SuppressFinalize(this);
        return ValueTask.CompletedTask;
    }

    protected static bool IsReadableDirectory(string path)
    {
        try
        {
            _ = Directory.EnumerateFileSystemEntries(path).Take(1).ToArray();
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (IOException)
        {
            return false;
        }
    }
}

public sealed class ClaudeCodeUsageProvider : UsageProviderBase
{
    private readonly IPathResolver _paths;
    private readonly IUsageStore _store;
    private readonly ClaudeCodeLogParser _parser = new();
    private readonly ClaudeUsageService _quotaService;
    private readonly UsageAggregator _aggregator;
    private readonly IClock _clock;
    private readonly int _maxFilesPerRefresh;
    private ClaudeUsageError? _lastQuotaError;

    public ClaudeCodeUsageProvider(
        IPathResolver paths,
        IUsageStore store,
        ClaudeUsageService? quotaService = null,
        UsageAggregator? aggregator = null,
        IClock? clock = null,
        int maxFilesPerRefresh = 40)
    {
        _paths = paths;
        _store = store;
        _clock = clock ?? SystemClock.Instance;
        _quotaService = quotaService ?? new ClaudeUsageService(new FileClaudeCredentialProvider(paths), clock: _clock);
        _aggregator = aggregator ?? new UsageAggregator();
        _maxFilesPerRefresh = maxFilesPerRefresh;
    }

    public override UsageProviderId Id => UsageProviderId.ClaudeCode;
    protected override IReadOnlyList<string> WatchPaths => [_paths.ClaudeProjects];
    public bool OAuthUsageEnabled { get; set; }

    public override Task<ProviderAvailability> CheckAvailabilityAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (OAuthUsageEnabled)
        {
            var failedSignIn = _lastQuotaError is
                ClaudeUsageError.SessionExpired or ClaudeUsageError.CredentialsNotFound or
                ClaudeUsageError.InvalidCredentials or ClaudeUsageError.Unauthorized or
                ClaudeUsageError.Forbidden;
            if (failedSignIn)
            {
                return Task.FromResult(new ProviderAvailability(
                    ProviderAvailabilityKind.NotLoggedIn,
                    "Open Claude Code and run /login, then refresh."));
            }
            if (_lastQuotaError == ClaudeUsageError.CredentialAccessDenied)
            {
                return Task.FromResult(new ProviderAvailability(
                    ProviderAvailabilityKind.PermissionDenied,
                    _paths.ClaudeCredentials));
            }
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.Available,
                "Claude usage via OAuth; local logs add token history when available.",
                true));
        }

        if (!Directory.Exists(_paths.ClaudeProjects))
        {
            return Task.FromResult(Directory.Exists(_paths.ClaudeHome)
                ? new ProviderAvailability(ProviderAvailabilityKind.NoData, $"No session logs in {_paths.ClaudeProjects}.")
                : new ProviderAvailability(ProviderAvailabilityKind.NotInstalled, $"{_paths.ClaudeHome} was not found."));
        }
        if (!IsReadableDirectory(_paths.ClaudeProjects))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.PermissionDenied,
                _paths.ClaudeProjects));
        }
        return Task.FromResult(_paths.EnumerateJsonlFiles(_paths.ClaudeProjects, 1).Count == 0
            ? new ProviderAvailability(ProviderAvailabilityKind.NoData, "No Claude Code transcripts yet.")
            : new ProviderAvailability(
                ProviderAvailabilityKind.Available,
                "Session logs — token counts only; local logs contain no quota percentage."));
    }

    public override async Task<UsageSnapshot> FetchCurrentUsageAsync(
        bool forceRefresh = false,
        CancellationToken cancellationToken = default)
    {
        var hasReadableLogs = Directory.Exists(_paths.ClaudeProjects) &&
            IsReadableDirectory(_paths.ClaudeProjects) &&
            _paths.EnumerateJsonlFiles(_paths.ClaudeProjects, 1).Count > 0;
        if (!hasReadableLogs && !OAuthUsageEnabled)
        {
            throw new UsageProviderException("Claude Code usage data is not available yet.");
        }

        string? latestModel = null;
        long? latestContext = null;
        DateTimeOffset? latestTimestamp = null;
        var malformed = 0;
        var candidates = 0;
        var files = hasReadableLogs
            ? _paths.EnumerateJsonlFiles(_paths.ClaudeProjects, _maxFilesPerRefresh)
            : [];

        foreach (var file in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            IncrementalReadResult read;
            try
            {
                read = JsonlReader.ReadNewLines(
                    file,
                    _store.GetCursor(file),
                    _store.GetCursorFingerprint(file));
            }
            catch (UsageProviderException)
            {
                continue;
            }
            if (read.Lines.Count == 0)
            {
                continue;
            }

            var result = _parser.Parse(read.Lines);
            malformed += result.MalformedLineCount;
            candidates += result.CandidateLineCount;
            _store.InsertEvents(result.Events);
            _store.SetCursor(file, read.NewOffset, read.PrefixFingerprint);
            if (result.LatestTimestamp is not null &&
                (latestTimestamp is null || result.LatestTimestamp >= latestTimestamp))
            {
                latestTimestamp = result.LatestTimestamp;
                latestModel = result.LatestModel;
                latestContext = result.LatestContextTokens;
            }
        }

        if (candidates > 20 && candidates == malformed)
        {
            throw new UsageProviderException("Claude Code transcript format appears to have changed.");
        }

        var weekEvents = _store.GetEvents(Id, _aggregator.Day(6, _clock.UtcNow));
        var today = _aggregator.TodayTotals(weekEvents, Id, _clock.UtcNow);
        latestModel ??= today is null ? _store.GetLatestModel(Id) : weekEvents.LastOrDefault()?.Model;
        var quota = OAuthUsageEnabled
            ? await _quotaService.GetUsageAsync(forceRefresh, cancellationToken).ConfigureAwait(false)
            : new ClaudeUsageFetchResult(null, null, false, null);
        _lastQuotaError = quota.Error;

        return UsageSnapshot.Create(
            Id,
            _clock.UtcNow,
            hasReadableLogs ? UsageSource.LocalLog : UsageSource.OfficialApi,
            latestModel,
            today?.InputTokens,
            today?.CachedInputTokens,
            today?.CacheCreationTokens,
            today?.OutputTokens,
            null,
            today?.TotalTokens,
            latestContext,
            null,
            quota.Usage?.FiveHour?.AsUsageWindow(5 * 60),
            quota.Usage?.SevenDay?.AsUsageWindow(7 * 24 * 60),
            quota.Usage?.SevenDaySonnet?.AsUsageWindow(7 * 24 * 60),
            quota.FetchedAt,
            quota.IsCached,
            quota.Error,
            OAuthUsageEnabled,
            _aggregator.SessionBlock(weekEvents, Id, now: _clock.UtcNow),
            _aggregator.RollingWindowUsage(weekEvents, Id, 7, _clock.UtcNow));
    }
}

public sealed class CodexUsageProvider : UsageProviderBase
{
    private readonly IPathResolver _paths;
    private readonly IUsageStore _store;
    private readonly CodexLogParser _parser;
    private readonly UsageAggregator _aggregator;
    private readonly IClock _clock;
    private readonly int _maxFilesPerRefresh;
    private UsageWindow? _lastShortWindow;
    private UsageWindow? _lastWeeklyWindow;
    private string? _lastPlanType;
    private long? _lastContextWindow;
    private string? _lastModel;
    private long? _lastContextTokens;
    private DateTimeOffset? _lastWindowUpdate;
    private bool _didRecoverCanonicalRateLimits;

    public CodexUsageProvider(
        IPathResolver paths,
        IUsageStore store,
        UsageAggregator? aggregator = null,
        IClock? clock = null,
        int maxFilesPerRefresh = 20)
    {
        _paths = paths;
        _store = store;
        _clock = clock ?? SystemClock.Instance;
        _parser = new CodexLogParser(_clock);
        _aggregator = aggregator ?? new UsageAggregator();
        _maxFilesPerRefresh = maxFilesPerRefresh;
    }

    public override UsageProviderId Id => UsageProviderId.Codex;
    protected override IReadOnlyList<string> WatchPaths => [_paths.CodexSessions];

    public override Task<ProviderAvailability> CheckAvailabilityAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!Directory.Exists(_paths.CodexHome))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.NotInstalled,
                $"{_paths.CodexHome} was not found."));
        }
        if (!Directory.Exists(_paths.CodexSessions))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.NoData,
                $"No session logs in {_paths.CodexSessions}."));
        }
        if (!IsReadableDirectory(_paths.CodexSessions))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.PermissionDenied,
                _paths.CodexSessions));
        }
        return Task.FromResult(_paths.EnumerateJsonlFiles(_paths.CodexSessions, 1).Count == 0
            ? new ProviderAvailability(ProviderAvailabilityKind.NoData, "No Codex rollout logs yet.")
            : new ProviderAvailability(
                ProviderAvailabilityKind.Available,
                "Rollout logs — token counts, usage percentage, and reset time.",
                true));
    }

    public override Task<UsageSnapshot> FetchCurrentUsageAsync(
        bool forceRefresh = false,
        CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(_paths.CodexSessions))
        {
            throw new UsageProviderException("Codex usage data is not available yet.");
        }

        var allFiles = _paths.EnumerateJsonlFiles(_paths.CodexSessions);
        var recent = allFiles.Take(_maxFilesPerRefresh);
        var backfill = allFiles.Skip(_maxFilesPerRefresh).Where(file => _store.GetCursor(file) == 0);
        var files = recent.Concat(backfill).ToArray();
        if (!_didRecoverCanonicalRateLimits)
        {
            _didRecoverCanonicalRateLimits = true;
            RecoverCanonicalRateLimits(files);
        }

        DateTimeOffset? newestParsed = null;
        foreach (var file in files.Reverse())
        {
            cancellationToken.ThrowIfCancellationRequested();
            IncrementalReadResult read;
            try
            {
                read = JsonlReader.ReadNewLines(
                    file,
                    _store.GetCursor(file),
                    _store.GetCursorFingerprint(file));
            }
            catch (UsageProviderException)
            {
                continue;
            }
            if (read.Lines.Count == 0)
            {
                continue;
            }

            var sessionId = SessionIdFromPath(file);
            var previous = read.DidReset
                ? new CumulativeTotals()
                : _store.GetSessionTotals(sessionId) ?? new CumulativeTotals();
            var result = _parser.Parse(
                read.Lines,
                sessionId,
                previous,
                _store.GetLatestModel(sessionId));
            _store.InsertEvents(result.Events);
            _store.SetSessionTotals(sessionId, Id, result.Totals);
            _store.SetCursor(file, read.NewOffset, read.PrefixFingerprint);

            if (result.LatestTimestamp is not null &&
                (newestParsed is null || result.LatestTimestamp >= newestParsed))
            {
                newestParsed = result.LatestTimestamp;
                _lastModel = result.LatestModel ?? _lastModel;
                _lastContextTokens = result.LatestContextTokens ?? _lastContextTokens;
                _lastContextWindow = result.ContextWindowTokens ?? _lastContextWindow;
            }
            if (result.ShortWindow is not null || result.WeeklyWindow is not null)
            {
                _lastShortWindow = result.ShortWindow ?? _lastShortWindow;
                _lastWeeklyWindow = result.WeeklyWindow ?? _lastWeeklyWindow;
                _lastPlanType = result.PlanType ?? _lastPlanType;
                _lastWindowUpdate = result.LatestRateLimitTimestamp ?? result.LatestTimestamp ?? _clock.UtcNow;
            }
        }

        var weekEvents = _store.GetEvents(Id, _aggregator.Day(6, _clock.UtcNow));
        var today = _aggregator.TodayTotals(weekEvents, Id, _clock.UtcNow);
        PersistLimits();
        RestoreLimits();
        _lastModel ??= _store.GetLatestModel(Id);
        var shortWindow = Expire(_lastShortWindow);
        var weeklyWindow = Expire(_lastWeeklyWindow);

        return Task.FromResult(UsageSnapshot.Create(
            Id,
            _clock.UtcNow,
            UsageSource.LocalLog,
            _lastModel,
            today?.InputTokens,
            today?.CachedInputTokens,
            null,
            today?.OutputTokens,
            today?.ReasoningTokens,
            today?.TotalTokens,
            _lastContextTokens,
            _lastContextWindow,
            shortWindow,
            weeklyWindow,
            null,
            null,
            false,
            null,
            false,
            shortWindow is null ? null : _aggregator.ReportedWindowUsage(weekEvents, Id, shortWindow),
            weeklyWindow is null ? null : _aggregator.ReportedWindowUsage(weekEvents, Id, weeklyWindow),
            _lastPlanType));
    }

    public static string SessionIdFromPath(string path)
    {
        var name = Path.GetFileNameWithoutExtension(path);
        var parts = name.Split('-');
        return parts.Length >= 5 ? string.Join('-', parts.TakeLast(5)) : name;
    }

    private void RecoverCanonicalRateLimits(IEnumerable<string> files)
    {
        foreach (var file in files)
        {
            try
            {
                var read = JsonlReader.ReadNewLines(file, 0);
                var result = _parser.ParseLatestRateLimits(read.Lines);
                if (!result.HasQuota)
                {
                    continue;
                }
                _lastShortWindow = result.ShortWindow;
                _lastWeeklyWindow = result.WeeklyWindow;
                _lastPlanType = result.PlanType;
                _lastWindowUpdate = _clock.UtcNow;
                return;
            }
            catch (UsageProviderException)
            {
                // Try the next recent log.
            }
        }
    }

    private void PersistLimits()
    {
        if (_lastShortWindow is not null)
        {
            _store.InsertLimitSample(Id, _lastWindowUpdate ?? _clock.UtcNow, "short", _lastShortWindow, UsageSource.LocalLog);
        }
        if (_lastWeeklyWindow is not null)
        {
            _store.InsertLimitSample(Id, _lastWindowUpdate ?? _clock.UtcNow, "weekly", _lastWeeklyWindow, UsageSource.LocalLog);
        }
    }

    private void RestoreLimits()
    {
        if (_lastShortWindow is null && _store.GetLatestLimitSample(Id, "short") is { } shortSample)
        {
            _lastShortWindow = shortSample.Window;
            _lastWindowUpdate ??= shortSample.Timestamp;
        }
        if (_lastWeeklyWindow is null && _store.GetLatestLimitSample(Id, "weekly") is { } weeklySample)
        {
            _lastWeeklyWindow = weeklySample.Window;
            _lastWindowUpdate ??= weeklySample.Timestamp;
        }
    }

    private UsageWindow? Expire(UsageWindow? window) =>
        window?.ResetsAt is not null && window.ResetsAt <= _clock.UtcNow ? null : window;
}

public sealed class CopilotUsageProvider : UsageProviderBase
{
    private readonly IPathResolver _paths;
    private readonly IUsageStore _store;
    private readonly CopilotLogParser _parser = new();
    private readonly UsageAggregator _aggregator;
    private readonly IClock _clock;
    private readonly int _maxFilesPerRefresh;
    private string? _lastModel;

    public CopilotUsageProvider(
        IPathResolver paths,
        IUsageStore store,
        UsageAggregator? aggregator = null,
        IClock? clock = null,
        int maxFilesPerRefresh = 20)
    {
        _paths = paths;
        _store = store;
        _aggregator = aggregator ?? new UsageAggregator();
        _clock = clock ?? SystemClock.Instance;
        _maxFilesPerRefresh = maxFilesPerRefresh;
    }

    public override UsageProviderId Id => UsageProviderId.CopilotCli;
    protected override IReadOnlyList<string> WatchPaths => [_paths.CopilotSessionState];

    public override Task<ProviderAvailability> CheckAvailabilityAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!Directory.Exists(_paths.CopilotHome))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.NotInstalled,
                $"{_paths.CopilotHome} was not found."));
        }
        if (!Directory.Exists(_paths.CopilotSessionState))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.NoData,
                $"No Copilot CLI sessions in {_paths.CopilotSessionState}."));
        }
        if (!IsReadableDirectory(_paths.CopilotSessionState))
        {
            return Task.FromResult(new ProviderAvailability(
                ProviderAvailabilityKind.PermissionDenied,
                _paths.CopilotSessionState));
        }
        return Task.FromResult(_paths.EnumerateCopilotEventFiles(1).Count == 0
            ? new ProviderAvailability(ProviderAvailabilityKind.NoData, "No Copilot CLI session logs yet.")
            : new ProviderAvailability(
                ProviderAvailabilityKind.Available,
                "Copilot CLI session logs — token counts only."));
    }

    public override Task<UsageSnapshot> FetchCurrentUsageAsync(
        bool forceRefresh = false,
        CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(_paths.CopilotSessionState))
        {
            throw new UsageProviderException("Copilot CLI usage data is not available yet.");
        }
        var allFiles = _paths.EnumerateCopilotEventFiles();
        var recent = allFiles.Take(_maxFilesPerRefresh);
        var backfill = allFiles.Skip(_maxFilesPerRefresh).Where(file => _store.GetCursor(file) == 0);
        foreach (var file in recent.Concat(backfill).Reverse())
        {
            cancellationToken.ThrowIfCancellationRequested();
            IncrementalReadResult read;
            try
            {
                read = JsonlReader.ReadNewLines(
                    file,
                    _store.GetCursor(file),
                    _store.GetCursorFingerprint(file));
            }
            catch (UsageProviderException)
            {
                continue;
            }
            if (read.Lines.Count == 0)
            {
                continue;
            }

            var sessionId = new DirectoryInfo(Path.GetDirectoryName(file)!).Name;
            var previous = read.DidReset
                ? new Dictionary<string, CumulativeTotals>()
                : StoredTotalsByModel(sessionId);
            var result = _parser.Parse(read.Lines, sessionId, previous);
            _store.InsertEvents(result.Events);
            foreach (var (model, totals) in result.TotalsByModel)
            {
                _store.SetSessionTotals($"{sessionId}|{model}", Id, totals);
            }
            _store.SetCursor(file, read.NewOffset, read.PrefixFingerprint);
            _lastModel = result.LatestModel ?? _lastModel;
        }

        var weekEvents = _store.GetEvents(Id, _aggregator.Day(6, _clock.UtcNow));
        var today = _aggregator.TodayTotals(weekEvents, Id, _clock.UtcNow);
        _lastModel ??= _store.GetLatestModel(Id);
        return Task.FromResult(UsageSnapshot.Create(
            Id,
            _clock.UtcNow,
            UsageSource.LocalLog,
            _lastModel,
            today?.InputTokens,
            today?.CachedInputTokens,
            today?.CacheCreationTokens,
            today?.OutputTokens,
            null,
            today?.TotalTokens));
    }

    private IReadOnlyDictionary<string, CumulativeTotals> StoredTotalsByModel(string sessionId)
    {
        var prefix = $"{sessionId}|";
        return _store.GetSessionModels(Id, prefix)
            .Select(model => (Model: model, Totals: _store.GetSessionTotals(prefix + model)))
            .Where(item => item.Totals is not null)
            .ToDictionary(item => item.Model, item => item.Totals!);
    }
}
