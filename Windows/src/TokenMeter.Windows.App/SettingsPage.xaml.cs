using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel;
using Windows.ApplicationModel.DataTransfer;
using Windows.Globalization;

namespace TokenMeter.Windows;

public sealed partial class SettingsPage : Page
{
    private bool _loading = true;
    private bool _changingStartup;
    private bool _changingClaudeOAuth;

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += SettingsPage_Loaded;
    }

    private async void SettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        var settings = AppServices.Settings;
        LocalizeOptionLabels();
        ClaudeToggle.IsOn = settings.ClaudeEnabled;
        CodexToggle.IsOn = settings.CodexEnabled;
        CopilotToggle.IsOn = settings.CopilotEnabled;
        ClaudeOAuthToggle.IsOn = settings.ClaudeOAuthUsageEnabled;
        FiveHourToggle.IsOn = settings.ShowFiveHourWindow;
        WeeklyToggle.IsOn = settings.ShowWeeklyWindow;
        ResetNotificationToggle.IsOn = settings.NotifyOnReset;
        ErrorNotificationToggle.IsOn = settings.NotifyOnDataError;
        SelectByTag(RefreshIntervalBox, settings.RefreshIntervalMinutes.ToString(System.Globalization.CultureInfo.InvariantCulture));
        SelectByTag(ThresholdBox, settings.NotificationThreshold.ToString(System.Globalization.CultureInfo.InvariantCulture));
        SelectByTag(RetentionBox, settings.RetentionDays.ToString(System.Globalization.CultureInfo.InvariantCulture));
        SelectByTag(LanguageBox, settings.AppLanguage);
        DiagnosticText.Text = BuildDiagnostics();

        try
        {
            var task = await StartupTask.GetAsync("TokenMeterStartup");
            StartupToggle.IsOn = task.State == StartupTaskState.Enabled;
            StartupToggle.IsEnabled = task.State != StartupTaskState.DisabledByUser;
            StartupStatus.Text = task.State == StartupTaskState.DisabledByUser
                ? L.Get("StartupDisabledByUser")
                : L.Get("StartupStatusReady");
        }
        catch (Exception error)
        {
            StartupToggle.IsEnabled = false;
            StartupStatus.Text = error.Message;
        }
        _loading = false;
    }

    private void Provider_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        var settings = AppServices.Settings;
        settings.ClaudeEnabled = ClaudeToggle.IsOn;
        settings.CodexEnabled = CodexToggle.IsOn;
        settings.CopilotEnabled = CopilotToggle.IsOn;
        settings.NotifyMonitorSettingsChanged();
    }

    private async void MonitorSetting_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading || _changingClaudeOAuth) return;

        var settings = AppServices.Settings;
        if (ClaudeOAuthToggle.IsOn && !settings.ClaudeOAuthUsageEnabled)
        {
            var content = new StackPanel { Spacing = 12 };
            content.Children.Add(new TextBlock
            {
                Text = L.Get("ClaudeConsentMessage"),
                TextWrapping = TextWrapping.Wrap,
            });
            content.Children.Add(new HyperlinkButton
            {
                Content = L.Get("PrivacyPolicy"),
                NavigateUri = new Uri("https://github.com/TakeruF/token_meter/blob/main/docs/privacy.md"),
                Padding = new Thickness(0),
            });
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = L.Get("ClaudeConsentTitle"),
                Content = content,
                PrimaryButtonText = L.Get("EnableClaudeUsage"),
                CloseButtonText = L.Get("Cancel"),
                DefaultButton = ContentDialogButton.Close,
            };
            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            {
                _changingClaudeOAuth = true;
                ClaudeOAuthToggle.IsOn = false;
                _changingClaudeOAuth = false;
                return;
            }
        }

        settings.ClaudeOAuthUsageEnabled = ClaudeOAuthToggle.IsOn;
        AppServices.Settings.NotifyMonitorSettingsChanged();
    }

    private void DisplaySetting_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        AppServices.Settings.ShowFiveHourWindow = FiveHourToggle.IsOn;
        AppServices.Settings.ShowWeeklyWindow = WeeklyToggle.IsOn;
    }

    private void Notification_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        AppServices.Settings.NotifyOnReset = ResetNotificationToggle.IsOn;
        AppServices.Settings.NotifyOnDataError = ErrorNotificationToggle.IsOn;
    }

    private async void Startup_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading || _changingStartup) return;
        _changingStartup = true;
        try
        {
            var task = await StartupTask.GetAsync("TokenMeterStartup");
            if (StartupToggle.IsOn)
            {
                var state = await task.RequestEnableAsync();
                StartupToggle.IsOn = state == StartupTaskState.Enabled;
            }
            else
            {
                task.Disable();
            }
            StartupStatus.Text = L.Get("StartupStatusReady");
        }
        catch (Exception error)
        {
            StartupStatus.Text = error.Message;
        }
        finally
        {
            _changingStartup = false;
        }
    }

    private void RefreshInterval_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || RefreshIntervalBox.SelectedItem is not ComboBoxItem item) return;
        AppServices.Settings.RefreshIntervalMinutes = ParseTag(item, 5);
        AppServices.Settings.NotifyMonitorSettingsChanged();
    }

    private void Threshold_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ThresholdBox.SelectedItem is not ComboBoxItem item) return;
        AppServices.Settings.NotificationThreshold = ParseTag(item, 20);
    }

    private void Retention_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || RetentionBox.SelectedItem is not ComboBoxItem item) return;
        AppServices.Settings.RetentionDays = ParseTag(item, 90);
        AppServices.Settings.NotifyMonitorSettingsChanged();
    }

    private async void ApplyLanguage_Click(object sender, RoutedEventArgs e)
    {
        if (LanguageBox.SelectedItem is not ComboBoxItem item) return;
        var language = item.Tag?.ToString() ?? string.Empty;
        if (language == AppServices.Settings.AppLanguage) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = L.Get("RestartRequiredTitle"),
            Content = L.Get("RestartRequiredMessage"),
            PrimaryButtonText = L.Get("RestartNow"),
            CloseButtonText = L.Get("Cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        AppServices.Settings.AppLanguage = language;
        ApplicationLanguages.PrimaryLanguageOverride = language;
        Microsoft.Windows.AppLifecycle.AppInstance.Restart(string.Empty);
    }

    private async void DeleteHistory_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = L.Get("DeleteHistoryTitle"),
            Content = L.Get("DeleteHistoryMessage"),
            PrimaryButtonText = L.Get("Delete"),
            CloseButtonText = L.Get("Cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        AppServices.Monitor.DeleteAllHistory();
        await AppServices.Monitor.RefreshAsync(RefreshReason.Manual, true);
        DiagnosticText.Text = BuildDiagnostics();
    }

    private void CopyDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage();
        package.SetText(BuildDiagnostics());
        Clipboard.SetContent(package);
    }

    private static string BuildDiagnostics() => string.Join(Environment.NewLine,
        $"Token Meter 1.3.0.0",
        $"OS: {Environment.OSVersion}",
        $"Events: {AppServices.Monitor.StoredEventCount}",
        $"Database: {AppServices.Paths.DatabasePath}",
        $"Claude: {AppServices.Paths.ClaudeProjects}",
        $"Codex: {AppServices.Paths.CodexSessions}",
        $"Copilot: {AppServices.Paths.CopilotSessionState}");

    private static int ParseTag(ComboBoxItem item, int fallback) =>
        int.TryParse(item.Tag?.ToString(), out var value) ? value : fallback;

    private static void SelectByTag(ComboBox box, string value)
    {
        foreach (var candidate in box.Items.OfType<ComboBoxItem>())
        {
            if ((candidate.Tag?.ToString() ?? string.Empty) == value)
            {
                box.SelectedItem = candidate;
                return;
            }
        }
    }

    private void LocalizeOptionLabels()
    {
        foreach (var item in RefreshIntervalBox.Items.OfType<ComboBoxItem>())
        {
            item.Content = string.Format(
                System.Globalization.CultureInfo.CurrentCulture,
                L.Get("MinutesFormat"),
                ParseTag(item, 5));
        }
        foreach (var item in RetentionBox.Items.OfType<ComboBoxItem>())
        {
            item.Content = string.Format(
                System.Globalization.CultureInfo.CurrentCulture,
                L.Get("DaysFormat"),
                ParseTag(item, 90));
        }
        foreach (var item in ThresholdBox.Items.OfType<ComboBoxItem>())
        {
            if (ParseTag(item, 0) == 0)
            {
                item.Content = L.Get("Off");
            }
        }
    }
}
