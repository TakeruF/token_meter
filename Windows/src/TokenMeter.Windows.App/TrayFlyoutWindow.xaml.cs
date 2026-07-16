using Microsoft.UI.Windowing;
using Windows.Graphics;

namespace TokenMeter.Windows;

public sealed partial class TrayFlyoutWindow : Window
{
    private readonly DashboardViewModel _viewModel;

    public TrayFlyoutWindow()
    {
        InitializeComponent();
        _viewModel = new DashboardViewModel(AppServices.Monitor);
        ProviderList.ItemsSource = _viewModel.ProviderCards;
        var scale = TrayNative.ScaleForWindow(this);
        AppWindow.Resize(new SizeInt32((int)(390 * scale), (int)(520 * scale)));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }
        Activated += TrayFlyoutWindow_Activated;
        AppServices.Monitor.Changed += Monitor_Changed;
    }

    public void ShowNearTaskbar()
    {
        _viewModel.Reload();
        NoProvidersLabel.Visibility = _viewModel.ProviderCards.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        var cursor = TrayNative.GetCursorPosition();
        var display = DisplayArea.GetFromPoint(cursor, DisplayAreaFallback.Nearest);
        var work = display.WorkArea;
        var scale = TrayNative.ScaleAtPoint(cursor);
        var width = (int)(390 * scale);
        var height = (int)(Math.Min(520, 126 + Math.Max(1, _viewModel.ProviderCards.Count) * 116) * scale);
        var x = Math.Clamp(cursor.X - width + 18, work.X, work.X + work.Width - width);
        var y = Math.Clamp(cursor.Y - height - 10, work.Y, work.Y + work.Height - height);
        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
        AppWindow.Show();
        Activate();
    }

    public void HideWindow() => AppWindow.Hide();

    private void TrayFlyoutWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            HideWindow();
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) =>
        await AppServices.Monitor.RefreshAsync(RefreshReason.Manual, true);

    private void Dashboard_Click(object sender, RoutedEventArgs e) => App.CurrentApp.ShowDashboard();

    private void Settings_Click(object sender, RoutedEventArgs e) => App.CurrentApp.ShowSettings();

    private void Monitor_Changed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            _viewModel.Reload();
            NoProvidersLabel.Visibility = _viewModel.ProviderCards.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        });
}

internal static class TrayNative
{
    private const uint MonitorDefaultToNearest = 2;

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    public static PointInt32 GetCursorPosition()
    {
        _ = GetCursorPos(out var point);
        return new PointInt32(point.X, point.Y);
    }

    public static double ScaleForWindow(Window window)
    {
        var handle = WinRT.Interop.WindowNative.GetWindowHandle(window);
        var dpi = GetDpiForWindow(handle);
        return dpi == 0 ? 1d : dpi / 96d;
    }

    public static double ScaleAtPoint(PointInt32 position)
    {
        var monitor = MonitorFromPoint(new Point { X = position.X, Y = position.Y }, MonitorDefaultToNearest);
        return monitor != 0 && GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0
            ? dpi / 96d
            : 1d;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint window);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern nint MonitorFromPoint(Point point, uint flags);

    [System.Runtime.InteropServices.DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(nint monitor, int dpiType, out uint dpiX, out uint dpiY);

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }
}
