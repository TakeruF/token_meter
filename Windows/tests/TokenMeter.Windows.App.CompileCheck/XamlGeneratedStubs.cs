namespace TokenMeter.Windows;

public partial class App
{
    private void InitializeComponent() { }
}

public sealed partial class MainWindow
{
    private Microsoft.UI.Xaml.Controls.NavigationView Navigation { get; } = new();
    private Microsoft.UI.Xaml.Controls.NavigationViewItem DashboardItem { get; } = new();
    private Microsoft.UI.Xaml.Controls.NavigationViewItem SettingsItem { get; } = new();
    private Microsoft.UI.Xaml.Controls.Frame ContentFrame { get; } = new();
    private void InitializeComponent() { }
}

public sealed partial class DashboardPage
{
    private UsageChart Chart { get; } = new();
    private Microsoft.UI.Xaml.Controls.ProgressBar RefreshProgress { get; } = new();
    private void InitializeComponent() { }
}

public sealed partial class UsageChart
{
    private Microsoft.UI.Xaml.Controls.Canvas Plot { get; } = new();
    private Microsoft.UI.Xaml.Controls.TextBlock EmptyLabel { get; } = new();
    private void InitializeComponent() { }
}

public sealed partial class SettingsPage
{
    private Microsoft.UI.Xaml.Controls.ToggleSwitch ClaudeToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch CodexToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch CopilotToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch ClaudeOAuthToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch FiveHourToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch WeeklyToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch ResetNotificationToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch ErrorNotificationToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ToggleSwitch StartupToggle { get; } = new();
    private Microsoft.UI.Xaml.Controls.ComboBox RefreshIntervalBox { get; } = new();
    private Microsoft.UI.Xaml.Controls.ComboBox ThresholdBox { get; } = new();
    private Microsoft.UI.Xaml.Controls.ComboBox RetentionBox { get; } = new();
    private Microsoft.UI.Xaml.Controls.ComboBox LanguageBox { get; } = new();
    private Microsoft.UI.Xaml.Controls.TextBlock StartupStatus { get; } = new();
    private Microsoft.UI.Xaml.Controls.TextBlock DiagnosticText { get; } = new();
    private void InitializeComponent() { }
}

public sealed partial class TrayFlyoutWindow
{
    private Microsoft.UI.Xaml.Controls.ItemsControl ProviderList { get; } = new();
    private Microsoft.UI.Xaml.Controls.TextBlock NoProvidersLabel { get; } = new();
    private void InitializeComponent() { }
}
