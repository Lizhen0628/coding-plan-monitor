using System;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using WinForms = System.Windows.Forms;

namespace CodingPlanMonitor;

public partial class App : Application
{
    private static Mutex? _mutex;
    private bool _ownsMutex;

    private SettingsStore _store = null!;
    private MonitorViewModel _vm = null!;
    private WinForms.NotifyIcon? _tray;
    private PanelWindow _panel = null!;
    private SettingsWindow? _settings;
    private DispatcherTimer? _timer;
    private IntPtr _trayIconHandle = IntPtr.Zero;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _mutex = new Mutex(true, @"Global\CodingPlanMonitorSingleInstance", out bool created);
        _ownsMutex = created;
        if (!created)
        {
            Shutdown();
            return;
        }

        _store = SettingsStore.Load();
        _vm = new MonitorViewModel(_store);
        _vm.StateChanged += OnStateChanged;

        _panel = new PanelWindow(_vm);
        _panel.OpenSettingsRequested += OpenSettings;
        _panel.QuitRequested += Shutdown;

        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add("打开面板", null, (_, _) => _panel.TogglePanel());
        menu.Items.Add("刷新", null, (_, _) => { _ = _vm.RefreshAsync(); });
        menu.Items.Add("设置…", null, (_, _) => OpenSettings());
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("退出 Coding Plan Monitor", null, (_, _) => Shutdown());

        _tray = new WinForms.NotifyIcon
        {
            Text = "Coding Plan Monitor",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.MouseClick += (_, args) =>
        {
            if (args.Button == WinForms.MouseButtons.Left) _panel.TogglePanel();
        };

        UpdateTray();
        RestartTimer();
        _ = _vm.RefreshAsync();
    }

    private void OpenSettings()
    {
        if (_settings == null)
        {
            _settings = new SettingsWindow(_vm);
            _settings.Closed += (_, _) => _settings = null;
        }
        _settings.Show();
        if (_settings.WindowState == WindowState.Minimized) _settings.WindowState = WindowState.Normal;
        _settings.Activate();
    }

    private void OnStateChanged()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(OnStateChanged);
            return;
        }
        RestartTimer();
        UpdateTray();
    }

    private void RestartTimer()
    {
        _timer ??= CreateTimer();
        var interval = TimeSpan.FromMinutes(Math.Clamp(_store.RefreshMinutes, 1, 60));
        if (_timer.Interval != interval) _timer.Interval = interval;
        _timer.Stop();
        _timer.Start();
    }

    private DispatcherTimer CreateTimer()
    {
        var timer = new DispatcherTimer();
        timer.Tick += (_, _) => { _ = _vm.RefreshAsync(); };
        return timer;
    }

    private void UpdateTray()
    {
        if (_tray == null) return;

        // 托盘图标显示第一个监控账号的 5 小时用量百分比（可在设置中关闭）
        int? pct = null;
        if (_store.ShowMenuBarUsage)
        {
            var first = _vm.MonitoredAccounts.FirstOrDefault();
            if (first != null && _vm.Usages.TryGetValue(first.Id, out var usage) && usage.FiveHour != null)
                pct = (int)Math.Round(usage.FiveHour.Percentage);
        }

        var (icon, handle) = TrayIconRenderer.Create(pct);
        var oldHandle = _trayIconHandle;
        _tray.Icon = icon;
        _trayIconHandle = handle;
        if (oldHandle != IntPtr.Zero) TrayIconRenderer.DestroyHandle(oldHandle);

        var tip = "Coding Plan Monitor";
        if (_vm.LastRefresh != null)
        {
            var title = _vm.MenuBarTitle;
            tip = title == "--" ? tip : $"{title}（上次 {_vm.LastRefresh:HH:mm}）";
        }
        _tray.Text = tip.Length > 63 ? tip[..63] : tip;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_tray != null)
        {
            _tray.Visible = false;
            _tray.Dispose();
            _tray = null;
        }
        if (_trayIconHandle != IntPtr.Zero)
        {
            TrayIconRenderer.DestroyHandle(_trayIconHandle);
            _trayIconHandle = IntPtr.Zero;
        }
        if (_ownsMutex)
        {
            try { _mutex?.ReleaseMutex(); } catch { /* 忽略 */ }
        }
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
