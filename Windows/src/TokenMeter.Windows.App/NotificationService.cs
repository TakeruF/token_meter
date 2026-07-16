using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace TokenMeter.Windows;

public sealed class NotificationService : IDisposable
{
    private static readonly int[] Thresholds = [20, 10, 5];
    private readonly UsageMonitor _monitor;
    private readonly AppSettings _settings;
    private readonly HashSet<string> _delivered = [];
    private readonly Dictionary<UsageProviderId, string> _lastErrors = [];
    private bool _registered;

    public NotificationService(UsageMonitor monitor, AppSettings settings)
    {
        _monitor = monitor;
        _settings = settings;
        _delivered.UnionWith(settings.DeliveredNotificationKeys);
    }

    public void Initialize()
    {
        try
        {
            AppNotificationManager.Default.Register();
            _registered = true;
            _monitor.SnapshotUpdated += Monitor_SnapshotUpdated;
            _monitor.Changed += Monitor_Changed;
        }
        catch (Exception error)
        {
            System.Diagnostics.Debug.WriteLine($"Notifications unavailable: {error.Message}");
        }
    }

    public void Dispose()
    {
        _monitor.SnapshotUpdated -= Monitor_SnapshotUpdated;
        _monitor.Changed -= Monitor_Changed;
        if (_registered)
        {
            try
            {
                AppNotificationManager.Default.Unregister();
            }
            catch (Exception error)
            {
                System.Diagnostics.Debug.WriteLine($"Notification unregister failed: {error.Message}");
            }
        }
        GC.SuppressFinalize(this);
    }

    private void Monitor_SnapshotUpdated(
        object? sender,
        (UsageProviderId Provider, UsageSnapshot? Previous, UsageSnapshot Current) update)
    {
        if (!_registered) return;
        foreach (var (kind, current, previous) in Windows(update.Current, update.Previous))
        {
            if (current?.RemainingRatio is not double currentRatio) continue;
            var currentPercent = currentRatio * 100;
            var previousPercent = previous?.RemainingRatio is double previousRatio ? previousRatio * 100 : 101;
            var displayName = $"{update.Provider.DisplayName()} · {L.Get(kind)}";

            if (_settings.NotificationThreshold > 0)
            {
                foreach (var threshold in Thresholds.Where(value => value <= _settings.NotificationThreshold))
                {
                    if (currentPercent > threshold || previousPercent <= threshold) continue;
                    var period = current.ResetsAt?.ToUnixTimeSeconds().ToString(
                        System.Globalization.CultureInfo.InvariantCulture) ?? "unknown";
                    var key = $"limit|{update.Provider}|{kind}|{period}|{threshold}";
                    if (!Remember(key)) continue;
                    Show(
                        string.Format(
                            System.Globalization.CultureInfo.CurrentCulture,
                            L.Get("LimitNotificationTitle"),
                            displayName),
                        string.Format(
                            System.Globalization.CultureInfo.CurrentCulture,
                            L.Get("LimitNotificationBody"),
                            threshold,
                            DisplayFormatting.RelativeReset(current.ResetsAt)));
                }
            }

            if (_settings.NotifyOnReset && previous?.RemainingRatio is double oldRatio &&
                currentRatio > oldRatio + 0.05)
            {
                var period = current.ResetsAt?.ToUnixTimeSeconds().ToString(
                    System.Globalization.CultureInfo.InvariantCulture) ?? DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(
                    System.Globalization.CultureInfo.InvariantCulture);
                var key = $"reset|{update.Provider}|{kind}|{period}";
                if (Remember(key))
                {
                    Show(
                        string.Format(
                            System.Globalization.CultureInfo.CurrentCulture,
                            L.Get("ResetNotificationTitle"),
                            displayName),
                        L.Get("ResetNotificationBody"));
                }
            }
        }
    }

    private static IEnumerable<(string Kind, UsageWindow? Current, UsageWindow? Previous)> Windows(
        UsageSnapshot current,
        UsageSnapshot? previous)
    {
        yield return ("ShortWindowName", current.ShortWindow, previous?.ShortWindow);
        yield return ("WeeklyWindowName", current.WeeklyWindow, previous?.WeeklyWindow);
        yield return ("SonnetWeeklyWindowName", current.SonnetWeeklyWindow, previous?.SonnetWeeklyWindow);
    }

    private bool Remember(string key)
    {
        if (!_delivered.Add(key)) return false;
        _settings.RememberNotification(key);
        return true;
    }

    private void Monitor_Changed(object? sender, EventArgs e)
    {
        if (!_registered || !_settings.NotifyOnDataError) return;
        foreach (var pair in _monitor.States)
        {
            var error = pair.Value.LastError;
            if (string.IsNullOrWhiteSpace(error))
            {
                _lastErrors.Remove(pair.Key);
                continue;
            }
            if (_lastErrors.GetValueOrDefault(pair.Key) == error) continue;
            _lastErrors[pair.Key] = error;
            Show(
                string.Format(
                    System.Globalization.CultureInfo.CurrentCulture,
                    L.Get("DataErrorNotificationTitle"),
                    pair.Key.DisplayName()),
                L.Get("DataErrorNotificationBody"));
        }
    }

    private static void Show(string title, string body)
    {
        var notification = new AppNotificationBuilder()
            .AddText(title)
            .AddText(body)
            .BuildNotification();
        AppNotificationManager.Default.Show(notification);
    }
}
