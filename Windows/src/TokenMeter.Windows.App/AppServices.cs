using Windows.Storage;

namespace TokenMeter.Windows;

public static class AppServices
{
    public static AppSettings Settings { get; private set; } = null!;
    public static WindowsPathResolver Paths { get; private set; } = null!;
    public static UsageMonitor Monitor { get; private set; } = null!;
    public static NotificationService Notifications { get; private set; } = null!;
    public static TrayIconService? Tray { get; set; }

    public static void Initialize()
    {
        Settings = new AppSettings();
        Paths = new WindowsPathResolver(appDataRoot: ApplicationData.Current.LocalFolder.Path);
        var store = new SqliteUsageStore(Paths.DatabasePath);
        var providers = new IUsageProvider[]
        {
            new ClaudeCodeUsageProvider(Paths, store),
            new CodexUsageProvider(Paths, store),
            new CopilotUsageProvider(Paths, store),
        };
        Monitor = new UsageMonitor(providers, store, () => Settings.ToMonitorOptions());
        Notifications = new NotificationService(Monitor, Settings);
    }
}
