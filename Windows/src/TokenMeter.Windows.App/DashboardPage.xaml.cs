namespace TokenMeter.Windows;

public sealed partial class DashboardPage : Page
{
    private readonly DashboardViewModel _viewModel;

    public DashboardPage()
    {
        InitializeComponent();
        _viewModel = new DashboardViewModel(AppServices.Monitor);
        DataContext = _viewModel;
        _viewModel.ChartChanged += ViewModel_ChartChanged;
        AppServices.Monitor.Changed += Monitor_Changed;
        Loaded += DashboardPage_Loaded;
        Unloaded += DashboardPage_Unloaded;
    }

    private void DashboardPage_Loaded(object sender, RoutedEventArgs e) => Chart.SetValues(_viewModel.ChartValues);

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        RefreshProgress.Visibility = Visibility.Visible;
        await AppServices.Monitor.RefreshAsync(RefreshReason.Manual, true);
        RefreshProgress.Visibility = Visibility.Collapsed;
    }

    private void Monitor_Changed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            _viewModel.Reload();
            RefreshProgress.Visibility = AppServices.Monitor.IsRefreshing ? Visibility.Visible : Visibility.Collapsed;
        });

    private void ViewModel_ChartChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() => Chart.SetValues(_viewModel.ChartValues));

    private void DashboardPage_Unloaded(object sender, RoutedEventArgs e)
    {
        AppServices.Monitor.Changed -= Monitor_Changed;
        _viewModel.ChartChanged -= ViewModel_ChartChanged;
    }
}
