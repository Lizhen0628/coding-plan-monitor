using System;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Threading;

namespace CodingPlanMonitor;

/// <summary>设置窗口（对应 macOS 版 SettingsView）：账号列表 + 凭证编辑 + 通用设置</summary>
public partial class SettingsWindow : Window
{
    private readonly MonitorViewModel _vm;
    private bool _suppress;
    private Guid? _selectedId;

    public SettingsWindow(MonitorViewModel vm)
    {
        InitializeComponent();
        _vm = vm;

        AddButton.Click += AddButton_Click;
        RemoveButton.Click += (_, _) => RemoveSelected();
        AccountListBox.SelectionChanged += (_, _) =>
        {
            if (_suppress) return;
            _selectedId = (AccountListBox.SelectedItem as ListBoxItem)?.Tag as Guid?;
            RebuildDetail();
        };

        // 通用页
        for (int i = 1; i <= 60; i++) RefreshCombo.Items.Add(i);
        _suppress = true;
        RefreshCombo.SelectedItem = _vm.Store.RefreshMinutes;
        ShowUsageCheck.IsChecked = _vm.Store.ShowMenuBarUsage;
        _suppress = false;

        RefreshCombo.SelectionChanged += (_, _) =>
        {
            if (_suppress || RefreshCombo.SelectedItem is not int minutes) return;
            _vm.Store.RefreshMinutes = minutes;
            SaveAndNotify(refresh: false);
        };
        ShowUsageCheck.Click += (_, _) =>
        {
            if (_suppress) return;
            _vm.Store.ShowMenuBarUsage = ShowUsageCheck.IsChecked == true;
            SaveAndNotify(refresh: false);
        };

        RebuildList();
    }

    // MARK: - 账号列表

    private Account? SelectedAccount =>
        _selectedId is { } id ? _vm.Accounts.FirstOrDefault(a => a.Id == id) : null;

    private void RebuildList()
    {
        _suppress = true;
        AccountListBox.Items.Clear();
        foreach (var account in _vm.Accounts)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(Ui.Badge(account.Provider, 20));
            panel.Children.Add(new TextBlock
            {
                Text = _vm.DisplayName(account),
                FontSize = 13,
                Margin = new Thickness(8, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            });
            AccountListBox.Items.Add(new ListBoxItem { Content = panel, Tag = account.Id, Padding = new Thickness(6, 4, 6, 4) });
        }

        // 恢复/修正选中项
        if (_selectedId == null || _vm.Accounts.All(a => a.Id != _selectedId))
            _selectedId = _vm.Accounts.FirstOrDefault()?.Id;
        if (_selectedId is { } selected)
        {
            foreach (ListBoxItem item in AccountListBox.Items)
            {
                if (item.Tag is Guid id && id == selected)
                {
                    AccountListBox.SelectedItem = item;
                    break;
                }
            }
        }
        _suppress = false;
        RebuildDetail();
    }

    private void AddButton_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        foreach (var provider in ProviderInfo.All)
        {
            var p = provider;
            var item = new MenuItem { Header = ProviderInfo.DisplayName(p) };
            item.Click += (_, _) =>
            {
                var account = _vm.AddAccount(p);
                _selectedId = account.Id;
                RebuildList();
                SaveAndNotify(refresh: false);
            };
            menu.Items.Add(item);
        }
        menu.PlacementTarget = AddButton;
        menu.Placement = PlacementMode.Bottom;
        menu.IsOpen = true;
    }

    private void RemoveSelected()
    {
        if (SelectedAccount is not { } account) return;
        var result = MessageBox.Show(this, $"确定删除「{_vm.DisplayName(account)}」吗？",
            "删除账号", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (result != MessageBoxResult.Yes) return;
        _vm.RemoveAccount(account);
        _selectedId = _vm.Accounts.FirstOrDefault()?.Id;
        RebuildList();
        SaveAndNotify(refresh: true);
    }

    // MARK: - 账号详情

    private void RebuildDetail()
    {
        DetailPanel.Children.Clear();
        if (SelectedAccount is not { } account)
        {
            DetailPanel.Children.Add(new TextBlock
            {
                Text = "选择左侧账号进行编辑\n或点击左下角「＋ 添加账号」",
                Foreground = Ui.SecondaryText,
                FontSize = 12,
                TextAlignment = TextAlignment.Center,
                Margin = new Thickness(0, 40, 0, 0),
            });
            return;
        }

        // 供应商
        var providerRow = new StackPanel { Orientation = Orientation.Horizontal };
        providerRow.Children.Add(Ui.Badge(account.Provider, 22));
        providerRow.Children.Add(new TextBlock
        {
            Text = ProviderInfo.DisplayName(account.Provider),
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        });
        DetailPanel.Children.Add(providerRow);

        // 备注名
        DetailPanel.Children.Add(SectionHeader("账号信息"));
        DetailPanel.Children.Add(FieldLabel($"备注名（可选，如「{ProviderInfo.NameExample(account.Provider)}」）"));
        var nameBox = new TextBox { Text = account.Name, Width = 280, HorizontalAlignment = HorizontalAlignment.Left };
        nameBox.LostFocus += (_, _) =>
        {
            var value = nameBox.Text.Trim();
            if (value == account.Name) return;
            account.Name = value;
            SaveAndNotify(refresh: false);
            RebuildListKeepSelection();
        };
        DetailPanel.Children.Add(nameBox);

        // 监控开关
        DetailPanel.Children.Add(SectionHeader("监控"));
        var visibleCheck = new CheckBox { IsChecked = account.IsVisible, Content = "在监控面板显示用量" };
        visibleCheck.Click += (_, _) =>
        {
            account.IsVisible = visibleCheck.IsChecked == true;
            SaveAndNotify(refresh: true);
        };
        DetailPanel.Children.Add(visibleCheck);
        DetailPanel.Children.Add(Caption("关闭后该订阅不在监控面板与托盘中显示，也不再自动刷新"));

        // 凭证区（按供应商形态）
        BuildCredentialSection(account);

        // GLM 平台
        if (account.Provider == Provider.Glm)
        {
            DetailPanel.Children.Add(SectionHeader("平台"));
            DetailPanel.Children.Add(BuildCombo(
                new[] { ("bigmodel", "国内（bigmodel.cn）"), ("zai", "国际（z.ai）") },
                account.GlmPlatform,
                value => account.GlmPlatform = value));
        }

        // 区域（通义 / MiniMax）
        if (ProviderInfo.RegionOptions(account.Provider) is { } regionOptions)
        {
            DetailPanel.Children.Add(SectionHeader("区域"));
            DetailPanel.Children.Add(BuildCombo(regionOptions, account.Region, value => account.Region = value));
            if (ProviderInfo.RegionCaption(account.Provider) is { } caption)
                DetailPanel.Children.Add(Caption(caption));
        }

        // 凭证获取帮助
        DetailPanel.Children.Add(SectionHeader("帮助"));
        var link = new Hyperlink(new Run("在控制台获取凭证 →"))
        {
            NavigateUri = new Uri(ProviderInfo.KeyHelpUrl(account.Provider)),
        };
        link.RequestNavigate += (_, args) =>
        {
            Process.Start(new ProcessStartInfo(args.Uri.AbsoluteUri) { UseShellExecute = true });
            args.Handled = true;
        };
        DetailPanel.Children.Add(new TextBlock(link) { FontSize = 12 });

        // 删除
        DetailPanel.Children.Add(SectionHeader(""));
        var deleteButton = new Button
        {
            Content = "删除该账号",
            Foreground = Ui.Red,
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(10, 3, 10, 3),
        };
        deleteButton.Click += (_, _) => RemoveSelected();
        DetailPanel.Children.Add(deleteButton);
    }

    private void BuildCredentialSection(Account account)
    {
        switch (ProviderInfo.Kind(account.Provider))
        {
            case CredentialKind.ApiKey:
                DetailPanel.Children.Add(SectionHeader("API Key"));
                DetailPanel.Children.Add(SecretField(
                    $"API Key（{ProviderInfo.KeyPlaceholder(account.Provider)}）",
                    account.ApiKey, value => account.ApiKey = value));
                if (account.Provider == Provider.Copilot)
                {
                    DetailPanel.Children.Add(BuildImportRow("从本机 GitHub Copilot 导入", account, () =>
                    {
                        var token = LocalCredentialImporter.CopilotOAuthToken();
                        return token != null ? (token, (string?)null) : null;
                    }));
                    DetailPanel.Children.Add(Caption(
                        "需先在本机登录 GitHub Copilot；Token 也可从 ~/.config/github-copilot/hosts.json 手动获取"));
                }
                DetailPanel.Children.Add(Caption($"在 {ProviderInfo.DisplayName(account.Provider)} 控制台获取凭证后粘贴到上方"));
                break;

            case CredentialKind.AkSk:
                DetailPanel.Children.Add(SectionHeader("访问凭证（AK/SK）"));
                DetailPanel.Children.Add(SecretField("AccessKey ID（AKLT…）", account.ApiKey,
                    value => account.ApiKey = value));
                DetailPanel.Children.Add(SecretField("Secret Access Key（从 IAM 控制台获取）", account.SecretKey,
                    value => account.SecretKey = value));
                DetailPanel.Children.Add(Caption($"在 {ProviderInfo.DisplayName(account.Provider)} 控制台创建 AK/SK 后粘贴到上方"));
                break;

            case CredentialKind.ClaudeOAuth:
                DetailPanel.Children.Add(SectionHeader("OAuth Token"));
                DetailPanel.Children.Add(SecretField(
                    $"OAuth Token（{ProviderInfo.KeyPlaceholder(account.Provider)}）",
                    account.ApiKey, value => account.ApiKey = value));
                DetailPanel.Children.Add(BuildImportRow("从本机 Claude Code 导入", account, () =>
                {
                    var token = LocalCredentialImporter.ClaudeOAuthToken();
                    return token != null ? (token, (string?)null) : null;
                }));
                DetailPanel.Children.Add(Caption("需先在本机登录 Claude Code；Token 也可从 ~/.claude/.credentials.json 手动获取"));
                break;

            case CredentialKind.CodexOAuth:
                DetailPanel.Children.Add(SectionHeader("Codex 凭证"));
                DetailPanel.Children.Add(SecretField("Access Token", account.ApiKey,
                    value => account.ApiKey = value));
                DetailPanel.Children.Add(SecretField("Account ID（可选，多账号时必填）", account.SecretKey,
                    value => account.SecretKey = value));
                DetailPanel.Children.Add(BuildImportRow("从本机 Codex CLI 导入", account, () =>
                {
                    var credentials = LocalCredentialImporter.CodexCredentials();
                    return credentials != null ? (credentials.Value.AccessToken, (string?)credentials.Value.AccountId) : null;
                }));
                DetailPanel.Children.Add(Caption("需先在本机登录 Codex CLI；凭证也可从 ~/.codex/auth.json 手动获取"));
                break;

            case CredentialKind.GeminiOAuth:
                DetailPanel.Children.Add(SectionHeader("OAuth 凭证"));
                DetailPanel.Children.Add(SecretField(
                    $"Refresh Token（{ProviderInfo.KeyPlaceholder(account.Provider)}）",
                    account.ApiKey, value => account.ApiKey = value));
                DetailPanel.Children.Add(BuildImportRow("从本机 Gemini CLI 导入", account, () =>
                {
                    var token = LocalCredentialImporter.GeminiRefreshToken();
                    return token != null ? (token, (string?)null) : null;
                }));
                DetailPanel.Children.Add(Caption("需先在本机登录 Gemini CLI（gemini 命令）；凭证位于 ~/.gemini/oauth_creds.json"));
                break;
        }
    }

    /// <summary>导入按钮 + 结果提示；成功时回填凭证并触发刷新</summary>
    private UIElement BuildImportRow(string title, Account account, Func<(string Token, string? Secondary)?> import)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        var button = new Button { Content = title, Padding = new Thickness(10, 3, 10, 3) };
        var message = new TextBlock
        {
            FontSize = 11,
            Foreground = Ui.SecondaryText,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        button.Click += (_, _) =>
        {
            if (import() is { } result)
            {
                account.ApiKey = result.Token;
                if (!string.IsNullOrEmpty(result.Secondary)) account.SecretKey = result.Secondary;
                message.Text = "✓ 已导入";
                SaveAndNotify(refresh: true);
                RebuildDetail();
            }
            else
            {
                message.Text = "未找到本机凭据，请手动粘贴";
            }
            ClearMessageLater(message);
        };
        row.Children.Add(button);
        row.Children.Add(message);
        return row;
    }

    private void ClearMessageLater(TextBlock message)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            message.Text = "";
        };
        timer.Start();
    }

    // MARK: - 控件构造辅助

    private static TextBlock SectionHeader(string text) => new()
    {
        Text = text,
        FontSize = 13,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 16, 0, 6),
    };

    private static TextBlock FieldLabel(string text) => new()
    {
        Text = text,
        FontSize = 11,
        Foreground = Ui.SecondaryText,
        Margin = new Thickness(0, 4, 0, 2),
    };

    private static TextBlock Caption(string text) => new()
    {
        Text = text,
        FontSize = 11,
        Foreground = Ui.TertiaryText,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 4, 0, 0),
    };

    /// <summary>密码输入框（标签在上）；失焦时保存并刷新</summary>
    private UIElement SecretField(string label, string value, Action<string> onChange)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 2, 0, 4) };
        panel.Children.Add(FieldLabel(label));
        var box = new PasswordBox
        {
            Password = value,
            Width = 280,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        box.LostFocus += (_, _) =>
        {
            var trimmed = box.Password.Trim();
            if (trimmed == value) return;
            onChange(trimmed);
            SaveAndNotify(refresh: true);
        };
        panel.Children.Add(box);
        return panel;
    }

    /// <summary>下拉选项（值/标签对）；切换时保存并刷新</summary>
    private UIElement BuildCombo((string Value, string Label)[] options, string current, Action<string> onChange)
    {
        var combo = new ComboBox { Width = 300, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(6, 2, 6, 2) };
        foreach (var (value, label) in options)
            combo.Items.Add(new ComboBoxItem { Content = label, Tag = value });

        _suppress = true;
        foreach (ComboBoxItem item in combo.Items)
        {
            if (item.Tag as string == current)
            {
                combo.SelectedItem = item;
                break;
            }
        }
        _suppress = false;

        combo.SelectionChanged += (_, _) =>
        {
            if (_suppress || (combo.SelectedItem as ComboBoxItem)?.Tag is not string value) return;
            onChange(value);
            SaveAndNotify(refresh: true);
        };
        return combo;
    }

    // MARK: - 保存与通知

    private void SaveAndNotify(bool refresh)
    {
        _vm.Store.Save();
        if (refresh) _ = _vm.RefreshAsync();
        else _vm.NotifyChanged();
    }

    private void RebuildListKeepSelection()
    {
        var keep = _selectedId;
        RebuildList();
        _selectedId = keep;
        if (keep != null)
        {
            _suppress = true;
            foreach (ListBoxItem item in AccountListBox.Items)
            {
                if (item.Tag is Guid id && id == keep)
                {
                    AccountListBox.SelectedItem = item;
                    break;
                }
            }
            _suppress = false;
        }
    }
}
