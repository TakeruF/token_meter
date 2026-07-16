namespace TokenMeter.Core;

public sealed class DebouncedDirectoryWatcher : IDisposable
{
    private readonly IReadOnlyList<string> _paths;
    private readonly TimeSpan _debounce;
    private readonly object _gate = new();
    private readonly List<FileSystemWatcher> _watchers = [];
    private Func<Task>? _onChange;
    private Timer? _timer;
    private bool _disposed;

    public DebouncedDirectoryWatcher(IEnumerable<string> paths, TimeSpan? debounce = null)
    {
        _paths = paths.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        _debounce = debounce ?? TimeSpan.FromSeconds(3);
    }

    public void Start(Func<Task> onChange)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        lock (_gate)
        {
            if (_watchers.Count > 0)
            {
                return;
            }
            _onChange = onChange;
            foreach (var path in _paths.Where(Directory.Exists))
            {
                var watcher = new FileSystemWatcher(path)
                {
                    IncludeSubdirectories = true,
                    NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                    Filter = "*.jsonl",
                    EnableRaisingEvents = true,
                };
                watcher.Changed += OnChanged;
                watcher.Created += OnChanged;
                watcher.Deleted += OnChanged;
                watcher.Renamed += OnRenamed;
                watcher.Error += OnError;
                _watchers.Add(watcher);
            }
        }
    }

    public void Stop()
    {
        lock (_gate)
        {
            _timer?.Dispose();
            _timer = null;
            foreach (var watcher in _watchers)
            {
                watcher.EnableRaisingEvents = false;
                watcher.Dispose();
            }
            _watchers.Clear();
            _onChange = null;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        Stop();
        _disposed = true;
    }

    private void OnChanged(object sender, FileSystemEventArgs args) => Schedule();
    private void OnRenamed(object sender, RenamedEventArgs args) => Schedule();
    private void OnError(object sender, ErrorEventArgs args) => Schedule();

    private void Schedule()
    {
        lock (_gate)
        {
            _timer?.Dispose();
            _timer = new Timer(
                async _ =>
                {
                    var callback = _onChange;
                    if (callback is not null)
                    {
                        try
                        {
                            await callback().ConfigureAwait(false);
                        }
                        catch
                        {
                            // The periodic refresh is the recovery path. A watcher callback
                            // must never terminate the process.
                        }
                    }
                },
                null,
                _debounce,
                Timeout.InfiniteTimeSpan);
        }
    }
}
