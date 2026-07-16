using Microsoft.UI.Windowing;
using Windows.Graphics;

namespace TokenMeter.Windows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        var scale = TrayNative.ScaleForWindow(this);
        AppWindow.Resize(new SizeInt32((int)(1120 * scale), (int)(760 * scale)));
        AppWindow.SetIcon("Assets\\TokenMeter.ico");
        AppWindow.Closing += AppWindow_Closing;
        Navigation.SelectedItem = DashboardItem;
    }

    public void ShowDashboard()
    {
        Navigation.SelectedItem = DashboardItem;
        if (ContentFrame.CurrentSourcePageType != typeof(DashboardPage))
        {
            ContentFrame.Navigate(typeof(DashboardPage));
        }
    }

    public void ShowSettings()
    {
        Navigation.SelectedItem = SettingsItem;
        if (ContentFrame.CurrentSourcePageType != typeof(SettingsPage))
        {
            ContentFrame.Navigate(typeof(SettingsPage));
        }
    }

    public void ShowWindow()
    {
        AppWindow.Show();
        Activate();
    }

    public async Task ShowOnboardingAsync()
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = L.Get("WelcomeTitle"),
            Content = L.Get("WelcomeMessage"),
            PrimaryButtonText = L.Get("GetStarted"),
            DefaultButton = ContentDialogButton.Primary,
        };
        await dialog.ShowAsync();
        AppServices.Settings.HasCompletedSetup = true;
        ShowSettings();
    }

    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag?.ToString() == "settings")
        {
            ShowSettings();
        }
        else
        {
            ShowDashboard();
        }
    }

    private void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (App.CurrentApp.IsExiting)
        {
            return;
        }
        args.Cancel = true;
        sender.Hide();
    }
}
