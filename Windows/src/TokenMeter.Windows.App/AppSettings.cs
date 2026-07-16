using Windows.Storage;

namespace TokenMeter.Windows;

public sealed class AppSettings : INotifyPropertyChanged
{
    private readonly ApplicationDataContainer _values = ApplicationData.Current.LocalSettings;

    public event PropertyChangedEventHandler? PropertyChanged;

    public bool ClaudeEnabled
    {
        get => Get(nameof(ClaudeEnabled), true);
        set => Set(nameof(ClaudeEnabled), value);
    }

    public bool CodexEnabled
    {
        get => Get(nameof(CodexEnabled), true);
        set => Set(nameof(CodexEnabled), value);
    }

    public bool CopilotEnabled
    {
        get => Get(nameof(CopilotEnabled), false);
        set => Set(nameof(CopilotEnabled), value);
    }

    public bool ClaudeOAuthUsageEnabled
    {
        get => Get(nameof(ClaudeOAuthUsageEnabled), false);
        set => Set(nameof(ClaudeOAuthUsageEnabled), value);
    }

    public int RefreshIntervalMinutes
    {
        get => Get(nameof(RefreshIntervalMinutes), 5);
        set => Set(nameof(RefreshIntervalMinutes), Math.Clamp(value, 1, 60));
    }

    public int RetentionDays
    {
        get => Get(nameof(RetentionDays), 90);
        set => Set(nameof(RetentionDays), value is 30 or 90 or 180 or 365 ? value : 90);
    }

    public int NotificationThreshold
    {
        get => Get(nameof(NotificationThreshold), 20);
        set => Set(nameof(NotificationThreshold), value is 0 or 5 or 10 or 20 ? value : 20);
    }

    public bool NotifyOnReset
    {
        get => Get(nameof(NotifyOnReset), true);
        set => Set(nameof(NotifyOnReset), value);
    }

    public bool NotifyOnDataError
    {
        get => Get(nameof(NotifyOnDataError), true);
        set => Set(nameof(NotifyOnDataError), value);
    }

    public bool ShowFiveHourWindow
    {
        get => Get(nameof(ShowFiveHourWindow), true);
        set => Set(nameof(ShowFiveHourWindow), value);
    }

    public bool ShowWeeklyWindow
    {
        get => Get(nameof(ShowWeeklyWindow), true);
        set => Set(nameof(ShowWeeklyWindow), value);
    }

    public bool HasCompletedSetup
    {
        get => Get(nameof(HasCompletedSetup), false);
        set => Set(nameof(HasCompletedSetup), value);
    }

    public string AppLanguage
    {
        get => GetString(nameof(AppLanguage), string.Empty);
        set => SetString(nameof(AppLanguage), value);
    }

    public IReadOnlySet<UsageProviderId> EnabledProviders
    {
        get
        {
            var result = new HashSet<UsageProviderId>();
            if (ClaudeEnabled) result.Add(UsageProviderId.ClaudeCode);
            if (CodexEnabled) result.Add(UsageProviderId.Codex);
            if (CopilotEnabled) result.Add(UsageProviderId.CopilotCli);
            return result;
        }
    }

    public UsageMonitorOptions ToMonitorOptions() => new(
        EnabledProviders,
        ClaudeOAuthUsageEnabled,
        TimeSpan.FromMinutes(RefreshIntervalMinutes),
        RetentionDays);

    public IReadOnlyCollection<string> DeliveredNotificationKeys =>
        GetString(nameof(DeliveredNotificationKeys), string.Empty)
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    public void RememberNotification(string key)
    {
        var keys = DeliveredNotificationKeys
            .Append(key)
            .Distinct(StringComparer.Ordinal)
            .TakeLast(100);
        SetString(nameof(DeliveredNotificationKeys), string.Join('\n', keys));
    }

    public void NotifyMonitorSettingsChanged()
    {
        OnPropertyChanged(nameof(EnabledProviders));
        AppServices.Monitor.OptionsChanged();
    }

    private bool Get(string key, bool fallback) =>
        _values.Values.TryGetValue(key, out var value) && value is bool result ? result : fallback;

    private int Get(string key, int fallback) =>
        _values.Values.TryGetValue(key, out var value) && value is int result ? result : fallback;

    private string GetString(string key, string fallback) =>
        _values.Values.TryGetValue(key, out var value) && value is string result ? result : fallback;

    private void Set(string key, bool value)
    {
        if (Get(key, !value) == value)
        {
            return;
        }
        _values.Values[key] = value;
        OnPropertyChanged(key);
    }

    private void Set(string key, int value)
    {
        if (Get(key, int.MinValue) == value)
        {
            return;
        }
        _values.Values[key] = value;
        OnPropertyChanged(key);
    }

    private void SetString(string key, string value)
    {
        if (GetString(key, "\0") == value)
        {
            return;
        }
        _values.Values[key] = value;
        OnPropertyChanged(key);
    }

    private void OnPropertyChanged(string name) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
