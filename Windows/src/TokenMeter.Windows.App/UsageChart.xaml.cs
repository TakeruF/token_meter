using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace TokenMeter.Windows;

public sealed partial class UsageChart : UserControl
{
    private IReadOnlyList<long> _values = [];

    public UsageChart()
    {
        InitializeComponent();
    }

    public void SetValues(IReadOnlyList<long> values)
    {
        _values = values;
        Draw();
    }

    private void Plot_SizeChanged(object sender, SizeChangedEventArgs e) => Draw();

    private void Draw()
    {
        Plot.Children.Clear();
        var isEmpty = _values.Count == 0 || _values.All(value => value == 0);
        EmptyLabel.Visibility = isEmpty
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (isEmpty || Plot.ActualWidth <= 0 || Plot.ActualHeight <= 0)
        {
            return;
        }

        var max = Math.Max(1, _values.Max());
        var gap = _values.Count > 31 ? 1d : 3d;
        var slot = Plot.ActualWidth / _values.Count;
        var width = Math.Max(1, slot - gap);
        var brush = new SolidColorBrush((global::Windows.UI.Color)Application.Current.Resources["SystemAccentColor"]);
        for (var index = 0; index < _values.Count; index++)
        {
            var height = Math.Max(2, Plot.ActualHeight * _values[index] / max);
            var bar = new Rectangle
            {
                Width = width,
                Height = height,
                Fill = brush,
                RadiusX = Math.Min(3, width / 2),
                RadiusY = Math.Min(3, width / 2),
                Opacity = 0.86,
            };
            Canvas.SetLeft(bar, index * slot + gap / 2);
            Canvas.SetTop(bar, Plot.ActualHeight - height);
            Plot.Children.Add(bar);
        }
    }
}
