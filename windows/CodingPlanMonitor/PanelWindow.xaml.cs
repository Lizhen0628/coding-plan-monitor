using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace CodingPlanMonitor;

/// <summary>
/// 托盘弹出的监控面板（对应 macOS 版的 NSPopover）：
/// 账号行（紧凑摘要 + 点击展开详情）、状态行、操作按钮，点击外部自动收起。
/// </summary>
public partial class PanelWindow : Window
{
    private readonly MonitorViewModel _vm;

    /// <summary>已展开详情的账号（默认展开第一个，错误账号自动展开）</summary>
    private readonly HashSet<Guid> _expanded = new();
    private bool _expandInitialized;
    private readonly DispatcherTimer _tickTimer;

    public event Action? OpenSettingsRequested;
    public event Action? QuitRequested;

    public PanelWindow(MonitorViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        _vm.StateChanged += OnVmStateChanged;
        Deactivated += (_, _) => Hide();

        EmptySettingsButton.Click += (_, _) => OpenSettingsRequested?.Invoke();

        ActionsPanel.Children.Add(Ui.ActionRow("手动刷新", "↻", "Ctrl+R", () => { _ = _vm.RefreshAsync(); }));
        ActionsPanel.Children.Add(Ui.ActionRow("设置…", "⚙", "Ctrl+,", () => OpenSettingsRequested?.Invoke()));
        ActionsPanel.Children.Add(Ui.ActionRow("退出 Coding Plan Monitor", "⏻", "Ctrl+Q",
            () => QuitRequested?.Invoke(), isDestructive: true));

        // 周期刷新倒计时文案
        _tickTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _tickTimer.Tick += (_, _) => { if (IsVisible) RebuildRows(); };
        _tickTimer.Start();
    }

    private void OnVmStateChanged()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(OnVmStateChanged);
            return;
        }
        if (IsVisible) RefreshView();
    }

    public void TogglePanel()
    {
        if (IsVisible)
        {
            Hide();
            return;
        }
        RefreshView();
        Show();
        Activate();
        UpdateLayout();
        PositionNearTray();
    }

    /// <summary>停靠到任务栏通知区域附近（兼容任务栏位于四边的情况）</summary>
    private void PositionNearTray()
    {
        var wa = SystemParameters.WorkArea;
        double screenW = SystemParameters.PrimaryScreenWidth;
        double screenH = SystemParameters.PrimaryScreenHeight;

        if (wa.Top > 1 && Math.Abs(wa.Bottom - screenH) < 1)
        {
            // 任务栏在顶部
            Left = wa.Right - Width - 12;
            Top = wa.Top + 12;
        }
        else if (wa.Left > 1)
        {
            // 任务栏在左侧
            Left = wa.Left + 12;
            Top = wa.Bottom - ActualHeight - 12;
        }
        else
        {
            // 任务栏在底部（默认）或右侧
            Left = wa.Right - Width - 12;
            Top = wa.Bottom - ActualHeight - 12;
        }
    }

    private void RefreshView()
    {
        LoadingText.Visibility = _vm.IsLoading ? Visibility.Visible : Visibility.Collapsed;

        LastRefreshText.Text = _vm.LastRefresh is { } last ? $"上次刷新 {last:HH:mm:ss}" : "尚未刷新";
        if (_vm.IsOnline)
        {
            StatusDot.Fill = Ui.Green;
            StatusText.Text = "在线";
        }
        else if (_vm.LastRefresh != null)
        {
            StatusDot.Fill = Ui.Red;
            StatusText.Text = "异常";
        }
        else
        {
            StatusDot.Fill = Ui.Gray;
            StatusText.Text = "未知";
        }

        RebuildRows();
    }

    private void RebuildRows()
    {
        AccountList.Children.Clear();
        var accounts = _vm.MonitoredAccounts;

        EmptyState.Visibility = accounts.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ListScroller.Visibility = accounts.Count == 0 ? Visibility.Collapsed : Visibility.Visible;

        if (!_expandInitialized && accounts.Count > 0)
        {
            _expanded.Add(accounts[0].Id);
            _expandInitialized = true;
        }
        // 出错账号自动展开，让错误信息可见
        foreach (var id in _vm.Errors.Keys) _expanded.Add(id);

        foreach (var account in accounts)
            AccountList.Children.Add(BuildAccountRow(account));
    }

    // MARK: - 账号行（紧凑摘要 + 点击展开详情）

    private UIElement BuildAccountRow(Account account)
    {
        _vm.Usages.TryGetValue(account.Id, out var usage);
        _vm.Errors.TryGetValue(account.Id, out var error);
        var expanded = _expanded.Contains(account.Id);

        var container = new Border { CornerRadius = new CornerRadius(8), Margin = new Thickness(0, 1, 0, 1) };
        var stack = new StackPanel();
        container.Child = stack;

        // 摘要行（始终可见）
        var header = new Border
        {
            Background = Brushes.Transparent,
            Padding = new Thickness(8, 7, 8, 7),
            CornerRadius = new CornerRadius(8),
            Cursor = Cursors.Hand,
        };
        var headerGrid = new Grid();
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var badge = Ui.Badge(account.Provider, 26);
        headerGrid.Children.Add(badge);

        var nameStack = new StackPanel { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        nameStack.Children.Add(new TextBlock
        {
            Text = _vm.DisplayName(account),
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.PrimaryText,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        var subtitleText = usage?.Level is { Length: > 0 } level
            ? $"{ProviderInfo.DisplayName(account.Provider)} · {level.ToUpperInvariant()}"
            : ProviderInfo.DisplayName(account.Provider);
        nameStack.Children.Add(new TextBlock
        {
            Text = subtitleText,
            FontSize = 10,
            Foreground = Ui.TertiaryText,
        });
        Grid.SetColumn(nameStack, 1);
        headerGrid.Children.Add(nameStack);

        var meters = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (error != null)
        {
            meters.Children.Add(new TextBlock { Text = "⚠", FontSize = 13, Foreground = Ui.Orange, VerticalAlignment = VerticalAlignment.Center });
        }
        else if (usage != null)
        {
            if (usage.FiveHour != null) meters.Children.Add(BuildMiniMeter("5小时", usage.FiveHour.Percentage));
            if (usage.Weekly != null) meters.Children.Add(BuildMiniMeter("每周", usage.Weekly.Percentage));
            if (usage.Monthly != null) meters.Children.Add(BuildMiniMeter("每月", usage.Monthly.Percentage));
            foreach (var extra in usage.Extras) meters.Children.Add(BuildMiniMeter(extra.Label, extra.Percentage));
            if (usage.Balance != null) meters.Children.Add(BuildMiniBalance(usage.Balance));
        }
        else
        {
            meters.Children.Add(BuildMiniMeter("5小时", null));
        }
        Grid.SetColumn(meters, 2);
        headerGrid.Children.Add(meters);

        var chevron = new TextBlock
        {
            Text = expanded ? "▴" : "▾",
            FontSize = 10,
            Foreground = Ui.TertiaryText,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(chevron, 3);
        headerGrid.Children.Add(chevron);

        header.Child = headerGrid;
        header.MouseEnter += (_, _) => header.Background = Ui.Hover;
        header.MouseLeave += (_, _) => header.Background = Brushes.Transparent;
        header.MouseLeftButtonUp += (_, _) =>
        {
            if (!_expanded.Remove(account.Id)) _expanded.Add(account.Id);
            RebuildRows();
        };
        stack.Children.Add(header);

        // 展开的详情
        if (expanded)
            stack.Children.Add(BuildDetail(account, usage, error));

        return container;
    }

    private UIElement BuildDetail(Account account, ProviderUsage? usage, string? error)
    {
        var panel = new StackPanel { Margin = new Thickness(10, 2, 10, 10) };

        if (error != null)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 10) };
            row.Children.Add(new TextBlock { Text = "⚠ ", FontSize = 12, Foreground = Ui.Orange, VerticalAlignment = VerticalAlignment.Top });
            row.Children.Add(new TextBlock
            {
                Text = error,
                FontSize = 12,
                Foreground = Ui.PrimaryText,
                TextWrapping = TextWrapping.Wrap,
            });
            panel.Children.Add(row);
        }
        else
        {
            var id = account.Id.ToString("N");
            if (usage?.FiveHour != null || usage == null)
            {
                panel.Children.Add(BuildPercentageRow(
                    "🕐 5 小时额度",
                    usage?.FiveHour?.Percentage,
                    _vm.FiveHourSubtitle(usage?.FiveHour, $"{id}-fiveHour"),
                    () => _vm.ToggleCountdown($"{id}-fiveHour")));
            }
            if (usage?.Weekly is { } weekly)
            {
                panel.Children.Add(BuildPercentageRow(
                    "📅 每周额度",
                    weekly.Percentage,
                    _vm.WeeklySubtitle(weekly, $"{id}-weekly"),
                    () => _vm.ToggleCountdown($"{id}-weekly")));
            }
            if (usage?.Monthly is { } monthly)
                panel.Children.Add(BuildPercentageRow("🗓 每月总额度", monthly.Percentage, "", null));
            foreach (var extra in usage?.Extras ?? new List<ExtraQuota>())
                panel.Children.Add(BuildPercentageRow($"✨ {extra.Label}", extra.Percentage, "", null));
            if (usage?.Balance is { } balance)
                panel.Children.Add(BuildBalanceRow(balance));
            if (usage?.Mcp is { } mcp)
                panel.Children.Add(BuildMcpRow(mcp));
        }

        var (primary, secondary) = ProviderInfo.CredentialLabels(account.Provider);
        panel.Children.Add(BuildCopyKeyRow(primary, account.ApiKey));
        if (secondary != null && account.SecretKey.Trim().Length > 0)
            panel.Children.Add(BuildCopyKeyRow(secondary, account.SecretKey));
        panel.Children.Add(Ui.SeparatorLine(new Thickness(0, 8, 0, 0)));
        return panel;
    }

    // MARK: - 迷你额度表（收起状态下的一览）

    private UIElement BuildMiniMeter(string label, double? percentage)
    {
        var tint = Ui.TintFor(percentage);
        var panel = new StackPanel { Width = 44, Margin = new Thickness(4, 0, 0, 0) };
        panel.Children.Add(new TextBlock
        {
            Text = percentage is { } p ? $"{(int)p}%" : "--",
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            Foreground = percentage == null ? Ui.TertiaryText : tint,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        panel.Children.Add(new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = percentage ?? 0,
            Height = 4,
            Margin = new Thickness(5, 2, 5, 0),
            Foreground = tint,
            Background = Ui.TrackBg,
            BorderThickness = new Thickness(0),
        });
        panel.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 8,
            Foreground = Ui.TertiaryText,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        return panel;
    }

    private UIElement BuildMiniBalance(BalanceInfo balance)
    {
        var panel = new StackPanel { Width = 44, Margin = new Thickness(4, 0, 0, 0) };
        panel.Children.Add(new TextBlock
        {
            Text = $"{balance.Symbol}{balance.Total:0.##}",
            FontSize = 10,
            FontWeight = FontWeights.SemiBold,
            Foreground = balance.Total > 0 ? Ui.Accent : Ui.Red,
            HorizontalAlignment = HorizontalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        panel.Children.Add(new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = 0,
            Height = 4,
            Margin = new Thickness(5, 2, 5, 0),
            Background = Ui.TrackBg,
            BorderThickness = new Thickness(0),
            Visibility = Visibility.Hidden,
        });
        panel.Children.Add(new TextBlock
        {
            Text = "余额",
            FontSize = 8,
            Foreground = Ui.TertiaryText,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        return panel;
    }

    // MARK: - 详情行

    private UIElement BuildPercentageRow(string title, double? percentage, string subtitle, Action? onToggle)
    {
        var tint = Ui.TintFor(percentage);
        var panel = new StackPanel { Margin = new Thickness(0, 4, 0, 10) };

        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 12,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.PrimaryText,
        });
        var pctText = new TextBlock
        {
            Text = percentage is { } p ? $"{(int)p}%" : "--",
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Foreground = percentage == null ? Ui.SecondaryText : tint,
        };
        Grid.SetColumn(pctText, 1);
        top.Children.Add(pctText);
        panel.Children.Add(top);

        panel.Children.Add(new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = percentage ?? 0,
            Height = 5,
            Margin = new Thickness(0, 4, 0, 0),
            Foreground = tint,
            Background = Ui.TrackBg,
            BorderThickness = new Thickness(0),
        });

        if (subtitle.Length > 0 && onToggle != null)
        {
            var link = new TextBlock
            {
                Text = subtitle + "（点击切换）",
                FontSize = 11,
                Foreground = Ui.SecondaryText,
                Margin = new Thickness(0, 3, 0, 0),
                Cursor = Cursors.Hand,
            };
            link.MouseLeftButtonUp += (_, _) =>
            {
                onToggle();
                RebuildRows();
            };
            panel.Children.Add(link);
        }
        return panel;
    }

    private UIElement BuildMcpRow(McpUsage usage)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 4, 0, 10) };
        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.Children.Add(new TextBlock
        {
            Text = "🛡 MCP 每月",
            FontSize = 12,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.PrimaryText,
        });
        var count = new TextBlock
        {
            Text = $"{usage.Used:N0} / {usage.Total:N0} 次",
            FontSize = 12,
            Foreground = Ui.SecondaryText,
        };
        Grid.SetColumn(count, 1);
        top.Children.Add(count);
        panel.Children.Add(top);
        panel.Children.Add(new TextBlock
        {
            Text = $"剩余 {usage.Remaining:N0} 次",
            FontSize = 11,
            Foreground = Ui.SecondaryText,
            Margin = new Thickness(0, 2, 0, 0),
        });
        return panel;
    }

    private UIElement BuildBalanceRow(BalanceInfo balance)
    {
        var grid = new Grid { Margin = new Thickness(0, 4, 0, 10) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new TextBlock
        {
            Text = "💳 账户余额",
            FontSize = 12,
            FontWeight = FontWeights.Medium,
            Foreground = Ui.PrimaryText,
        });
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        if (balance.Granted > 0)
        {
            right.Children.Add(new TextBlock
            {
                Text = $"含赠送 {balance.Symbol}{balance.Granted:0.00}  ",
                FontSize = 11,
                Foreground = Ui.SecondaryText,
            });
        }
        right.Children.Add(new TextBlock
        {
            Text = $"{balance.Symbol}{balance.Total:0.00}",
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Foreground = balance.Total > 0 ? Ui.PrimaryText : Ui.Red,
        });
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);
        return grid;
    }

    private UIElement BuildCopyKeyRow(string label, string key)
    {
        var trimmed = key.Trim();
        var masked = trimmed.Length == 0
            ? "未设置"
            : trimmed.Length <= 6
                ? "***"
                : $"{trimmed[..3]}***{trimmed[^3..]}";

        var grid = new Grid { Margin = new Thickness(0, 2, 0, 2) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(new TextBlock
        {
            Text = "🔑 " + label,
            FontSize = 12,
            Foreground = Ui.PrimaryText,
            VerticalAlignment = VerticalAlignment.Center,
        });
        var maskedText = new TextBlock
        {
            Text = masked,
            FontSize = 10,
            FontFamily = new FontFamily("Consolas"),
            Foreground = Ui.SecondaryText,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(maskedText, 1);
        grid.Children.Add(maskedText);

        var copy = new TextBlock
        {
            Text = trimmed.Length == 0 ? "" : "复制",
            FontSize = 11,
            Foreground = Ui.SecondaryText,
            Cursor = Cursors.Hand,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            ToolTip = $"复制{label}",
        };
        copy.MouseLeftButtonUp += async (_, _) =>
        {
            if (trimmed.Length == 0) return;
            try { Clipboard.SetText(trimmed); }
            catch { return; }
            copy.Text = "✓ 已复制";
            copy.Foreground = Ui.Green;
            await Task.Delay(1500);
            copy.Text = "复制";
            copy.Foreground = Ui.SecondaryText;
        };
        Grid.SetColumn(copy, 2);
        grid.Children.Add(copy);
        return grid;
    }

    // MARK: - 快捷键

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.Control) return;
        switch (e.Key)
        {
            case Key.R:
                _ = _vm.RefreshAsync();
                e.Handled = true;
                break;
            case Key.OemComma:
                OpenSettingsRequested?.Invoke();
                e.Handled = true;
                break;
            case Key.Q:
                QuitRequested?.Invoke();
                e.Handled = true;
                break;
        }
    }
}
