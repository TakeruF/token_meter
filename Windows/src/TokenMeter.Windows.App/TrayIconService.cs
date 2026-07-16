using Microsoft.UI.Dispatching;
using System.Runtime.InteropServices;

namespace TokenMeter.Windows;

public sealed class TrayIconService : IDisposable
{
    private const uint WmApp = 0x8000;
    private const uint TrayMessage = WmApp + 42;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmRButtonUp = 0x0205;
    private const uint WmCommand = 0x0111;
    private const uint WmClose = 0x0010;
    private const uint WmDestroy = 0x0002;
    private const uint WmPowerBroadcast = 0x0218;
    private const uint PowerResumeAutomatic = 18;
    private const uint NimAdd = 0x00000000;
    private const uint NimDelete = 0x00000002;
    private const uint NifMessage = 0x00000001;
    private const uint NifIcon = 0x00000002;
    private const uint NifTip = 0x00000004;
    private const uint MfString = 0x00000000;
    private const uint TpmReturnCmd = 0x0100;
    private const uint TpmRightButton = 0x0002;
    private const int IdiApplication = 32512;
    private const uint ImageIcon = 1;
    private const uint LoadFromFile = 0x0010;
    private const uint LoadDefaultSize = 0x0040;

    private readonly DispatcherQueue _dispatcher;
    private readonly Action _showFlyout;
    private readonly Action _showDashboard;
    private readonly Action _refresh;
    private readonly Action _showSettings;
    private readonly Action _exit;
    private readonly ManualResetEventSlim _ready = new(false);
    private readonly WndProc _windowProc;
    private Thread? _thread;
    private nint _window;
    private nint _powerNotification;
    private nint _icon;
    private bool _ownsIcon;
    private bool _disposed;

    public TrayIconService(
        DispatcherQueue dispatcher,
        Action showFlyout,
        Action showDashboard,
        Action refresh,
        Action showSettings,
        Action exit)
    {
        _dispatcher = dispatcher;
        _showFlyout = showFlyout;
        _showDashboard = showDashboard;
        _refresh = refresh;
        _showSettings = showSettings;
        _exit = exit;
        _windowProc = WindowProc;
    }

    public void Initialize()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_thread is not null) return;
        _thread = new Thread(MessageLoop)
        {
            IsBackground = true,
            Name = "Token Meter tray icon",
        };
        _thread.Start();
        _ready.Wait(TimeSpan.FromSeconds(3));
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_window != 0)
        {
            _ = PostMessage(_window, WmClose, 0, 0);
        }
        _thread?.Join(TimeSpan.FromSeconds(2));
        _ready.Dispose();
        GC.SuppressFinalize(this);
    }

    private void MessageLoop()
    {
        var className = $"TokenMeterTray_{Environment.ProcessId}";
        var instance = GetModuleHandle(null);
        var windowClass = new WindowClass
        {
            Size = (uint)Marshal.SizeOf<WindowClass>(),
            Instance = instance,
            ClassName = className,
            WindowProcedure = Marshal.GetFunctionPointerForDelegate(_windowProc),
        };
        if (RegisterClassEx(ref windowClass) == 0)
        {
            _ready.Set();
            return;
        }

        _window = CreateWindowEx(0, className, "Token Meter", 0, 0, 0, 0, 0, new nint(-3), 0, instance, 0);
        if (_window == 0)
        {
            _ready.Set();
            return;
        }

        AddIcon();
        _powerNotification = RegisterSuspendResumeNotification(_window, 0);
        _ready.Set();
        while (GetMessage(out var message, 0, 0, 0) > 0)
        {
            _ = TranslateMessage(ref message);
            _ = DispatchMessage(ref message);
        }
        _ = UnregisterClass(className, instance);
    }

    private void AddIcon()
    {
        var data = CreateIconData();
        _icon = LoadImage(
            0,
            Path.Combine(AppContext.BaseDirectory, "Assets", "TokenMeter.ico"),
            ImageIcon,
            0,
            0,
            LoadFromFile | LoadDefaultSize);
        _ownsIcon = _icon != 0;
        if (_icon == 0)
        {
            _icon = LoadIcon(0, new nint(IdiApplication));
        }
        data.Icon = _icon;
        data.Flags = NifMessage | NifIcon | NifTip;
        _ = ShellNotifyIcon(NimAdd, ref data);
    }

    private IconData CreateIconData() => new()
    {
        Size = (uint)Marshal.SizeOf<IconData>(),
        Window = _window,
        Id = 1,
        CallbackMessage = TrayMessage,
        Tip = "Token Meter",
        Info = string.Empty,
        InfoTitle = string.Empty,
    };

    private nint WindowProc(nint window, uint message, nuint wParam, nint lParam)
    {
        if (message == TrayMessage)
        {
            var mouseMessage = unchecked((uint)lParam.ToInt64());
            if (mouseMessage == WmLButtonUp)
            {
                Enqueue(_showFlyout);
            }
            else if (mouseMessage == WmRButtonUp)
            {
                ShowContextMenu(window);
            }
            return 0;
        }

        if (message == WmCommand)
        {
            DispatchMenuCommand(unchecked((int)(wParam & 0xffff)));
            return 0;
        }

        if (message == WmPowerBroadcast && wParam == PowerResumeAutomatic)
        {
            Enqueue(_refresh);
            return 1;
        }

        if (message == WmClose)
        {
            if (_powerNotification != 0)
            {
                _ = UnregisterSuspendResumeNotification(_powerNotification);
                _powerNotification = 0;
            }
            var data = CreateIconData();
            _ = ShellNotifyIcon(NimDelete, ref data);
            if (_ownsIcon && _icon != 0)
            {
                _ = DestroyIcon(_icon);
                _icon = 0;
            }
            _ = DestroyWindow(window);
            return 0;
        }

        if (message == WmDestroy)
        {
            PostQuitMessage(0);
            return 0;
        }
        return DefWindowProc(window, message, wParam, lParam);
    }

    private void ShowContextMenu(nint window)
    {
        var menu = CreatePopupMenu();
        if (menu == 0) return;
        try
        {
            _ = AppendMenu(menu, MfString, 1, L.Get("Dashboard"));
            _ = AppendMenu(menu, MfString, 2, L.Get("Refresh"));
            _ = AppendMenu(menu, MfString, 3, L.Get("Settings"));
            _ = AppendMenu(menu, MfString, 4, L.Get("Exit"));
            var point = TrayNative.GetCursorPosition();
            _ = SetForegroundWindow(window);
            var command = TrackPopupMenu(menu, TpmReturnCmd | TpmRightButton, point.X, point.Y, 0, window, 0);
            DispatchMenuCommand(command);
        }
        finally
        {
            _ = DestroyMenu(menu);
        }
    }

    private void DispatchMenuCommand(int command)
    {
        var action = command switch
        {
            1 => _showDashboard,
            2 => _refresh,
            3 => _showSettings,
            4 => _exit,
            _ => null,
        };
        if (action is not null) Enqueue(action);
    }

    private void Enqueue(Action action) => _dispatcher.TryEnqueue(() => action());

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint WndProc(nint window, uint message, nuint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Size;
        public uint Style;
        public nint WindowProcedure;
        public int ClassExtra;
        public int WindowExtra;
        public nint Instance;
        public nint Icon;
        public nint Cursor;
        public nint Background;
        public string? MenuName;
        public string ClassName;
        public nint SmallIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        public nint Window;
        public uint Value;
        public nuint WParam;
        public nint LParam;
        public uint Time;
        public int X;
        public int Y;
        public uint Private;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct IconData
    {
        public uint Size;
        public nint Window;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State;
        public uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags;
        public Guid GuidItem;
        public nint BalloonIcon;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern ushort RegisterClassEx(ref WindowClass value);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool UnregisterClass(string value, nint instance);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern nint CreateWindowEx(uint exStyle, string className, string windowName, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint parameter);
    [DllImport("user32.dll")] private static extern nint DefWindowProc(nint window, uint message, nuint wParam, nint lParam);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(nint window);
    [DllImport("user32.dll")] private static extern bool PostMessage(nint window, uint message, nuint wParam, nint lParam);
    [DllImport("user32.dll")] private static extern int GetMessage(out Message message, nint window, uint min, uint max);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll")] private static extern nint DispatchMessage(ref Message message);
    [DllImport("user32.dll")] private static extern void PostQuitMessage(int exitCode);
    [DllImport("user32.dll")] private static extern nint LoadIcon(nint instance, nint iconName);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint LoadImage(nint instance, string name, uint type, int desiredWidth, int desiredHeight, uint load);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(nint icon);
    [DllImport("user32.dll")] private static extern nint CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool AppendMenu(nint menu, uint flags, nuint identifier, string text);
    [DllImport("user32.dll")] private static extern int TrackPopupMenu(nint menu, uint flags, int x, int y, int reserved, nint window, nint rectangle);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(nint menu);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint window);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern bool ShellNotifyIcon(uint message, ref IconData data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern nint GetModuleHandle(string? moduleName);
    [DllImport("powrprof.dll", SetLastError = true)] private static extern nint RegisterSuspendResumeNotification(nint recipient, uint flags);
    [DllImport("powrprof.dll", SetLastError = true)] private static extern bool UnregisterSuspendResumeNotification(nint handle);
}
