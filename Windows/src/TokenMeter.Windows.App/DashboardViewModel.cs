namespace TokenMeter.Windows;

public sealed record RangeOption(string Label, int Days);

public sealed record ProviderCardItem(
    string Name,
    string Status,
    string TodayTokens,
    double UsagePercent,
    string UsageText,
    string ResetText,
    string AccentBrushKey);

public sealed record ModelUsageItem(string Model, string Provider, string Tokens);

public sealed record SessionItem(string Provider, string Model, string When, string Turns, string Tokens);

public sealed class DashboardViewModel : INotifyPropertyChanged
{
    private readonly UsageMonitor _monitor;
    private readonly UsageAggregator _aggregator = new();
    private RangeOption _selectedRange;
    private string _totalTokens = "0";
    private string _inputTokens = "0";
    private string _cachedTokens = "0";
    private string _outputTokens = "0";
    private string _updatedAt = string.Empty;

    public DashboardViewModel(UsageMonitor monitor)
    {
        _monitor = monitor;
        Ranges =
        [
            new RangeOption(L.Get("Today"), 1),
            new RangeOption(L.Get("SevenDays"), 7),
            new RangeOption(L.Get("ThirtyDays"), 30),
            new RangeOption(L.Get("NinetyDays"), 90),
        ];
        _selectedRange = Ranges[1];
        Reload();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? ChartChanged;

    public IReadOnlyList<RangeOption> Ranges { get; }
    public ObservableCollection<ProviderCardItem> ProviderCards { get; } = [];
    public ObservableCollection<ModelUsageItem> Models { get; } = [];
    public ObservableCollection<SessionItem> Sessions { get; } = [];
    public IReadOnlyList<long> ChartValues { get; private set; } = [];

    public RangeOption SelectedRange
    {
        get => _selectedRange;
        set
        {
            if (_selectedRange == value)
            {
                return;
            }
            _selectedRange = value;
            OnPropertyChanged();
            Reload();
        }
    }

    public string TotalTokens { get => _totalTokens; private set => Set(ref _totalTokens, value); }
    public string InputTokens { get => _inputTokens; private set => Set(ref _inputTokens, value); }
    public string CachedTokens { get => _cachedTokens; private set => Set(ref _cachedTokens, value); }
    public string OutputTokens { get => _outputTokens; private set => Set(ref _outputTokens, value); }
    public string UpdatedAt { get => _updatedAt; private set => Set(ref _updatedAt, value); }

    public void Reload()
    {
        var enabled = AppServices.Settings.EnabledProviders;
        ProviderCards.Clear();
        var rangeEvents = new List<UsageEvent>();
        var chartLength = SelectedRange.Days == 1 ? DateTimeOffset.Now.Hour + 1 : SelectedRange.Days;
        var chartByDay = new long[Math.Max(1, chartLength)];

        foreach (var provider in enabled)
        {
            var events = _monitor.GetEvents(provider, SelectedRange.Days);
            rangeEvents.AddRange(events);
            var state = _monitor.States.GetValueOrDefault(provider);
            var today = _aggregator.TodayTotals(events, provider);
            var candidateWindows = new List<UsageWindow>();
            if (AppServices.Settings.ShowFiveHourWindow && state?.Snapshot?.ShortWindow is { } shortWindow)
            {
                candidateWindows.Add(shortWindow);
            }
            if (AppServices.Settings.ShowWeeklyWindow && state?.Snapshot?.WeeklyWindow is { } weeklyWindow)
            {
                candidateWindows.Add(weeklyWindow);
            }
            if (AppServices.Settings.ShowWeeklyWindow && state?.Snapshot?.SonnetWeeklyWindow is { } sonnetWindow)
            {
                candidateWindows.Add(sonnetWindow);
            }
            var window = candidateWindows.MinBy(item => item.RemainingRatio ?? 1d);
            var remaining = window?.RemainingRatio;
            var status = state?.LastError is not null
                ? L.Get("DataErrorStatus")
                : state is null
                    ? L.Get("NotChecked")
                    : L.Get(state.Availability.Kind switch
                    {
                        ProviderAvailabilityKind.Available => "AvailableStatus",
                        ProviderAvailabilityKind.NotInstalled => "NotInstalledStatus",
                        ProviderAvailabilityKind.NotLoggedIn => "NotLoggedInStatus",
                        ProviderAvailabilityKind.NoData => "NoDataStatus",
                        ProviderAvailabilityKind.PermissionDenied => "PermissionDeniedStatus",
                        _ => "NotChecked",
                    });
            var usageText = remaining is null
                ? L.Get("LocalUsageOnly")
                : string.Format(
                    System.Globalization.CultureInfo.CurrentCulture,
                    L.Get("RemainingFormat"),
                    DisplayFormatting.Percent(remaining.Value));
            ProviderCards.Add(new ProviderCardItem(
                provider.DisplayName(),
                status,
                DisplayFormatting.Tokens(today?.TotalTokens ?? 0),
                remaining is null ? 0 : remaining.Value * 100,
                usageText,
                DisplayFormatting.RelativeReset(window?.ResetsAt),
                provider switch
                {
                    UsageProviderId.ClaudeCode => "ClaudeBrush",
                    UsageProviderId.Codex => "CodexBrush",
                    _ => "CopilotBrush",
                }));

            var series = SelectedRange.Days == 1
                ? _aggregator.HourlySeries(events, provider)
                : _aggregator.DailySeries(events, provider, SelectedRange.Days);
            for (var index = 0; index < Math.Min(series.Count, chartByDay.Length); index++)
            {
                chartByDay[index] += series[index].TotalTokens;
            }
        }

        TotalTokens = DisplayFormatting.Tokens(rangeEvents.Sum(item => item.TotalTokens));
        InputTokens = DisplayFormatting.Tokens(rangeEvents.Sum(item => item.InputTokens));
        CachedTokens = DisplayFormatting.Tokens(rangeEvents.Sum(item => item.CachedInputTokens));
        OutputTokens = DisplayFormatting.Tokens(rangeEvents.Sum(item => item.OutputTokens));
        ChartValues = chartByDay;

        Models.Clear();
        foreach (var model in _aggregator.ModelBreakdown(rangeEvents).Take(12))
        {
            Models.Add(new ModelUsageItem(
                model.Model,
                model.Provider.DisplayName(),
                DisplayFormatting.Tokens(model.TotalTokens)));
        }

        Sessions.Clear();
        foreach (var session in _aggregator.RecentSessions(rangeEvents, 20))
        {
            Sessions.Add(new SessionItem(
                session.Provider.DisplayName(),
                session.Model ?? L.Get("UnknownModel"),
                session.End.LocalDateTime.ToString("g", System.Globalization.CultureInfo.CurrentCulture),
                string.Format(
                    System.Globalization.CultureInfo.CurrentCulture,
                    L.Get("TurnsFormat"),
                    session.Turns),
                DisplayFormatting.Tokens(session.TotalTokens)));
        }

        UpdatedAt = string.Format(
            System.Globalization.CultureInfo.CurrentCulture,
            L.Get("UpdatedFormat"),
            DateTime.Now.ToString("t", System.Globalization.CultureInfo.CurrentCulture));
        ChartChanged?.Invoke(this, EventArgs.Empty);
    }

    private void Set(ref string field, string value, [CallerMemberName] string? name = null)
    {
        if (field == value)
        {
            return;
        }
        field = value;
        OnPropertyChanged(name);
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
