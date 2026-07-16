using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel.Resources.Core;
using Windows.Globalization;

namespace TokenMeter.Windows;

public partial class App : Application
{
    private MainWindow? _mainWindow;
    private TrayFlyoutWindow? _trayFlyout;
    private bool _exiting;

    public App()
    {
        var storedLanguage = global::Windows.Storage.ApplicationData.Current.LocalSettings.Values["AppLanguage"] as string;
        if (!string.IsNullOrWhiteSpace(storedLanguage))
        {
            ApplicationLanguages.PrimaryLanguageOverride = storedLanguage;
        }
        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            System.Diagnostics.Debug.WriteLine(args.Exception);
        };
    }

    public static App CurrentApp => (App)Current;
    public MainWindow MainWindow => _mainWindow ?? throw new InvalidOperationException("The main window is not ready.");
    public bool IsExiting => _exiting;

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        var instance = AppInstance.FindOrRegisterForKey("TokenMeter.Main");
        if (!instance.IsCurrent)
        {
            await instance.RedirectActivationToAsync(activation);
            Environment.Exit(0);
            return;
        }

        instance.Activated += (_, _) =>
        {
            var window = _mainWindow;
            window?.DispatcherQueue.TryEnqueue(ShowDashboard);
        };
        AppServices.Initialize();
        _mainWindow = new MainWindow();
        _trayFlyout = new TrayFlyoutWindow();
        AppServices.Tray = new TrayIconService(
            _mainWindow.DispatcherQueue,
            ShowTrayFlyout,
            ShowDashboard,
            () => _ = AppServices.Monitor.RefreshAsync(RefreshReason.Manual, true),
            ShowSettings,
            ExitApplication);
        AppServices.Tray.Initialize();

        AppServices.Notifications.Initialize();
        var launchedAtStartup = activation.Kind == ExtendedActivationKind.StartupTask;
        if (!launchedAtStartup)
        {
            _mainWindow.Activate();
            _mainWindow.ShowDashboard();
        }
        await AppServices.Monitor.StartAsync();
        if (!launchedAtStartup && !AppServices.Settings.HasCompletedSetup)
        {
            await _mainWindow.ShowOnboardingAsync();
        }
    }

    public void ShowDashboard()
    {
        _trayFlyout?.HideWindow();
        MainWindow.ShowDashboard();
        MainWindow.ShowWindow();
    }

    public void ShowSettings()
    {
        _trayFlyout?.HideWindow();
        MainWindow.ShowSettings();
        MainWindow.ShowWindow();
    }

    public void ShowTrayFlyout()
    {
        _trayFlyout?.ShowNearTaskbar();
    }

    public async void ExitApplication()
    {
        if (_exiting)
        {
            return;
        }
        _exiting = true;
        AppServices.Tray?.Dispose();
        AppServices.Notifications.Dispose();
        await AppServices.Monitor.DisposeAsync();
        _trayFlyout?.Close();
        _mainWindow?.Close();
        Environment.Exit(0);
    }
}
