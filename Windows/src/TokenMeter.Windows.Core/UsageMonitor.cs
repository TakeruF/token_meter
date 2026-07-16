using System.Collections.Concurrent;

namespace TokenMeter.Core;

public enum RefreshReason
{
    Launch,
    Manual,
    LogChanged,
    Interval,
    Resume,
    DayChanged,
    SettingsChanged,
}

public sealed record UsageMonitorOptions(
    IReadOnlySet<UsageProviderId> EnabledProviders,
    bool ClaudeOAuthUsageEnabled,
    TimeSpan RefreshInterval,
    int RetentionDays)
{
    public static UsageMonitorOptions Default { get; } = new(
        new HashSet<UsageProviderId>
        {
            UsageProviderId.ClaudeCode,
            UsageProviderId.Codex,
        },
        false,
        TimeSpan.FromMinutes(5),
        90);
}

public sealed record ProviderState(
    ProviderAvailability Availability,
    UsageSnapshot? Snapshot,
    DateTimeOffset? LastSuccessfulUpdate,
    string? LastError);

public sealed class UsageMonitor : IAsyncDisposable
{
    private readonly IReadOnlyDictionary<UsageProviderId, IUsageProvider> _providers;
    private readonly IUsageStore _store;
    private readonly Func<UsageMonitorOptions> _options;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly ConcurrentDictionary<UsageProviderId, ProviderState> _states = new();
    private Timer? _timer;
    private Timer? _dayTimer;
    private TimeSpan? _appliedInterval;
    private bool _started;
    private bool _disposed;

    public UsageMonitor(
        IEnumerable<IUsageProvider> providers,
        IUsageStore store,
        Func<UsageMonitorOptions>? options = null)
    {
        _providers = providers.ToDictionary(provider => provider.Id);
        _store = store;
        _options = options ?? (() => UsageMonitorOptions.Default);
        foreach (var provider in _providers.Values)
        {
            _states[provider.Id] = new ProviderState(
                new ProviderAvailability(ProviderAvailabilityKind.NoData, "Not checked yet."),
                null,
                null,
                null);
        }
    }

    public event EventHandler? Changed;
    public event EventHandler<(UsageProviderId Provider, UsageSnapshot? Previous, UsageSnapshot Current)>? SnapshotUpdated;

    public IReadOnlyDictionary<UsageProviderId, ProviderState> States => _states;
    public bool IsRefreshing { get; private set; }
    public string? FatalError { get; private set; }
    public int StoredEventCount => _store.EventCount();

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_started)
        {
            return;
        }
        _started = true;
        ApplyOptions();
        ScheduleDayChange();
        await DetectDataSourcesAsync(cancellationToken).ConfigureAwait(false);
        await RefreshAsync(RefreshReason.Launch, false, cancellationToken).ConfigureAwait(false);
        foreach (var provider in _providers.Values)
        {
            provider.StartMonitoring(() => RefreshAsync(RefreshReason.LogChanged));
        }
    }

    public async Task DetectDataSourcesAsync(CancellationToken cancellationToken = default)
    {
        foreach (var provider in _providers.Values)
        {
            var availability = await provider.CheckAvailabilityAsync(cancellationToken).ConfigureAwait(false);
            _states.AddOrUpdate(
                provider.Id,
                _ => new ProviderState(availability, null, null, null),
                (_, old) => old with { Availability = availability });
        }
        OnChanged();
    }

    public async Task RefreshAsync(
        RefreshReason reason,
        bool forceRefresh = false,
        CancellationToken cancellationToken = default)
    {
        if (!await _refreshGate.WaitAsync(0, cancellationToken).ConfigureAwait(false))
        {
            return;
        }

        IsRefreshing = true;
        OnChanged();
        try
        {
            ApplyOptions();
            var options = _options();
            foreach (var providerId in options.EnabledProviders)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!_providers.TryGetValue(providerId, out var provider))
                {
                    continue;
                }

                try
                {
                    var availability = await provider.CheckAvailabilityAsync(cancellationToken).ConfigureAwait(false);
                    var previous = _states.GetValueOrDefault(providerId)?.Snapshot;
                    var snapshot = await provider.FetchCurrentUsageAsync(forceRefresh, cancellationToken)
                        .ConfigureAwait(false);
                    availability = await provider.CheckAvailabilityAsync(cancellationToken).ConfigureAwait(false);
                    _states[providerId] = new ProviderState(
                        availability,
                        snapshot,
                        snapshot.Timestamp,
                        null);
                    SnapshotUpdated?.Invoke(this, (providerId, previous, snapshot));
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception error)
                {
                    var old = _states.GetValueOrDefault(providerId);
                    _states[providerId] = new ProviderState(
                        old?.Availability ?? new ProviderAvailability(ProviderAvailabilityKind.NoData, error.Message),
                        old?.Snapshot,
                        old?.LastSuccessfulUpdate,
                        error.Message);
                }
            }
            _store.PruneEvents(options.RetentionDays);
            if (_started && reason is RefreshReason.Interval or RefreshReason.Resume or RefreshReason.SettingsChanged)
            {
                foreach (var provider in _providers.Values)
                {
                    provider.StopMonitoring();
                    provider.StartMonitoring(() => RefreshAsync(RefreshReason.LogChanged));
                }
            }
            FatalError = null;
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            FatalError = error.Message;
        }
        finally
        {
            IsRefreshing = false;
            _refreshGate.Release();
            OnChanged();
        }
    }

    public IReadOnlyList<UsageEvent> GetEvents(UsageProviderId provider, int days)
    {
        var aggregator = new UsageAggregator();
        return _store.GetEvents(provider, aggregator.Day(Math.Max(0, days - 1)));
    }

    public void DeleteAllHistory()
    {
        _store.DeleteAllData();
        foreach (var provider in _providers.Keys)
        {
            if (_states.TryGetValue(provider, out var state))
            {
                _states[provider] = state with { Snapshot = null, LastSuccessfulUpdate = null, LastError = null };
            }
        }
        OnChanged();
    }

    public void OptionsChanged()
    {
        ApplyOptions();
        _ = RefreshAsync(RefreshReason.SettingsChanged, true);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _timer?.Dispose();
        _dayTimer?.Dispose();
        foreach (var provider in _providers.Values)
        {
            await provider.DisposeAsync().ConfigureAwait(false);
        }
        _refreshGate.Dispose();
        _store.Dispose();
        GC.SuppressFinalize(this);
    }

    private void ApplyOptions()
    {
        var options = _options();
        if (_providers.GetValueOrDefault(UsageProviderId.ClaudeCode) is ClaudeCodeUsageProvider claude)
        {
            claude.OAuthUsageEnabled = options.ClaudeOAuthUsageEnabled;
        }
        if (_appliedInterval != options.RefreshInterval)
        {
            _timer?.Dispose();
            _timer = new Timer(
                _ => _ = RefreshAsync(RefreshReason.Interval),
                null,
                options.RefreshInterval,
                options.RefreshInterval);
            _appliedInterval = options.RefreshInterval;
        }
    }

    private void ScheduleDayChange()
    {
        _dayTimer?.Dispose();
        var now = DateTimeOffset.Now;
        var localDate = DateTime.SpecifyKind(now.LocalDateTime.Date.AddDays(1), DateTimeKind.Unspecified);
        if (TimeZoneInfo.Local.IsInvalidTime(localDate))
        {
            localDate = localDate.AddHours(1);
        }
        var nextDay = new DateTimeOffset(localDate, TimeZoneInfo.Local.GetUtcOffset(localDate));
        var due = nextDay - now;
        _dayTimer = new Timer(
            _ =>
            {
                _ = RefreshAsync(RefreshReason.DayChanged, true);
                ScheduleDayChange();
            },
            null,
            due,
            Timeout.InfiniteTimeSpan);
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}
