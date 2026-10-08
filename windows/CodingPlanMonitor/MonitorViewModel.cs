using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using CodingPlanMonitor.Services;

namespace CodingPlanMonitor;

/// <summary>监控核心：账号管理、并发刷新、凭证自动续期、文案格式化（对应 macOS 版 MonitorViewModel）</summary>
public sealed class MonitorViewModel
{
    private readonly object _gate = new();

    /// <summary>数据或设置变化时触发（UI 线程或后台线程，订阅方需自行调度）</summary>
    public event Action? StateChanged;

    public SettingsStore Store { get; }

    /// <summary>key 为账号 ID</summary>
    public Dictionary<Guid, ProviderUsage> Usages { get; } = new();
    public Dictionary<Guid, string> Errors { get; } = new();
    public DateTime? LastRefresh { get; private set; }
    public bool IsLoading { get; private set; }

    /// <summary>处于倒计时显示模式的行（key 为「账号ID-窗口」，点击切换），未包含的行显示重置时间点</summary>
    public HashSet<string> CountdownRows { get; } = new();

    public MonitorViewModel(SettingsStore store) => Store = store;

    // MARK: - 账号存取

    public List<Account> Accounts => Store.Accounts;

    public Account AddAccount(Provider provider)
    {
        var account = new Account { Provider = provider };
        Store.Accounts.Add(account);
        Store.Save();
        return account;
    }

    public void RemoveAccount(Account account)
    {
        Store.Accounts.RemoveAll(a => a.Id == account.Id);
        Usages.Remove(account.Id);
        Errors.Remove(account.Id);
        Store.Save();
    }

    // MARK: - 派生状态

    /// <summary>已配置凭证的账号</summary>
    public List<Account> ConfiguredAccounts => Accounts.Where(a => a.IsConfigured).ToList();

    /// <summary>实际参与监控与展示的账号（已配置 Key 且未被隐藏）</summary>
    public List<Account> MonitoredAccounts => ConfiguredAccounts.Where(a => a.IsVisible).ToList();

    public bool IsOnline => LastRefresh != null && Errors.Count == 0;

    /// <summary>面板显示名：优先用户备注名；同供应商多账号时自动编号</summary>
    public string DisplayName(Account account)
    {
        var name = account.Name.Trim();
        if (name.Length > 0) return name;
        var siblings = ConfiguredAccounts.Where(a => a.Provider == account.Provider).ToList();
        if (siblings.Count > 1)
        {
            var index = siblings.FindIndex(a => a.Id == account.Id);
            if (index >= 0) return $"{ProviderInfo.DisplayName(account.Provider)} {index + 1}";
        }
        return ProviderInfo.DisplayName(account.Provider);
    }

    /// <summary>紧凑标签：备注名（取前 4 字）或供应商前缀 + 编号</summary>
    public string ShortLabel(Account account)
    {
        var name = account.Name.Trim();
        if (name.Length > 0) return name.Length <= 4 ? name : name[..4];
        var siblings = ConfiguredAccounts.Where(a => a.Provider == account.Provider).ToList();
        if (siblings.Count > 1)
        {
            var index = siblings.FindIndex(a => a.Id == account.Id);
            if (index >= 0) return $"{ProviderInfo.ShortLabel(account.Provider)}{index + 1}";
        }
        return ProviderInfo.ShortLabel(account.Provider);
    }

    /// <summary>托盘 tooltip 文本：各账号 5 小时窗口已用百分比</summary>
    public string MenuBarTitle
    {
        get
        {
            var accounts = MonitoredAccounts;
            if (accounts.Count == 0) return "--";
            var parts = new List<string>();
            foreach (var account in accounts)
            {
                if (!Usages.TryGetValue(account.Id, out var usage) || usage.FiveHour == null) continue;
                var p = (int)usage.FiveHour.Percentage;
                parts.Add(accounts.Count > 1 ? $"{ShortLabel(account)}:{p}%" : $"{p}%");
            }
            return parts.Count == 0 ? "--" : string.Join(" ", parts);
        }
    }

    // MARK: - 刷新

    public async Task RefreshAsync()
    {
        lock (_gate)
        {
            if (IsLoading) return;
            IsLoading = true;
        }
        NotifyChanged();

        try
        {
            var targets = MonitoredAccounts;
            var validIds = targets.Select(a => a.Id).ToHashSet();

            // 清理已删除账号的缓存
            foreach (var key in Usages.Keys.Where(k => !validIds.Contains(k)).ToList()) Usages.Remove(key);
            foreach (var key in Errors.Keys.Where(k => !validIds.Contains(k)).ToList()) Errors.Remove(key);

            var results = await Task.WhenAll(targets.Select(FetchWithRetryAsync));
            foreach (var (account, usage, error) in results)
            {
                if (error == null && usage != null)
                {
                    Usages[account.Id] = usage;
                    Errors.Remove(account.Id);
                }
                else
                {
                    Usages.Remove(account.Id);
                    Errors[account.Id] = error ?? "未知错误";
                }
            }
            LastRefresh = DateTime.Now;
        }
        finally
        {
            lock (_gate) IsLoading = false;
            NotifyChanged();
        }
    }

    /// <summary>抓取一次；Token 类供应商（Claude/Codex/Gemini）凭证过期时自动从本机重新导入并重试一次</summary>
    private async Task<(Account Account, ProviderUsage? Usage, string? Error)> FetchWithRetryAsync(Account account)
    {
        try
        {
            return (account, await FetchAsync(account), null);
        }
        catch (Exception first)
        {
            var refreshed = ReimportCredentials(account);
            if (refreshed != null)
            {
                try
                {
                    var usage = await FetchAsync(refreshed);
                    account.ApiKey = refreshed.ApiKey;
                    account.SecretKey = refreshed.SecretKey;
                    Store.Save();
                    return (account, usage, null);
                }
                catch (Exception second)
                {
                    return (account, null, MessageFor(second));
                }
            }
            return (account, null, MessageFor(first));
        }
    }

    /// <summary>Claude/Codex/Gemini 凭证自动续期：仅读取本地文件</summary>
    private static Account? ReimportCredentials(Account account)
    {
        switch (account.Provider)
        {
            case Provider.Claude:
            {
                var token = LocalCredentialImporter.ClaudeOAuthToken();
                if (token == null || token == account.ApiKey) return null;
                var updated = account.Copy();
                updated.ApiKey = token;
                return updated;
            }
            case Provider.OpenAi:
            {
                var credentials = LocalCredentialImporter.CodexCredentials();
                if (credentials == null || credentials.Value.AccessToken == account.ApiKey) return null;
                var updated = account.Copy();
                updated.ApiKey = credentials.Value.AccessToken;
                if (credentials.Value.AccountId.Length > 0)
                    updated.SecretKey = credentials.Value.AccountId;
                return updated;
            }
            case Provider.Gemini:
            {
                var token = LocalCredentialImporter.GeminiRefreshToken();
                if (token == null || token == account.ApiKey) return null;
                var updated = account.Copy();
                updated.ApiKey = token;
                return updated;
            }
            default:
                return null;
        }
    }

    private static Task<ProviderUsage> FetchAsync(Account account)
    {
        var key = account.ApiKey.Trim();
        return account.Provider switch
        {
            Provider.Glm => GLMService.FetchAsync(key,
                account.GlmPlatform == "zai" ? "https://api.z.ai" : "https://open.bigmodel.cn"),
            Provider.Kimi => KimiService.FetchAsync(key),
            Provider.Volcengine => VolcengineService.FetchAsync(key, account.SecretKey),
            Provider.Alibaba => AlibabaService.FetchAsync(key, account.Region),
            Provider.Claude => ClaudeService.FetchAsync(key),
            Provider.OpenAi => OpenAIService.FetchAsync(key, account.SecretKey),
            Provider.MiniMax => MiniMaxService.FetchAsync(key, account.Region),
            Provider.Copilot => CopilotService.FetchAsync(key),
            Provider.Gemini => GeminiService.FetchAsync(key),
            Provider.DeepSeek => DeepSeekService.FetchAsync(key),
            _ => throw QuotaServiceError.InvalidResponse,
        };
    }

    private static string MessageFor(Exception error) => error switch
    {
        QuotaServiceError q => q.Message,
        HttpRequestException => "网络连接异常",
        TaskCanceledException => "网络连接异常",
        OperationCanceledException => "网络连接异常",
        JsonException => "响应数据格式异常",
        _ => error.Message,
    };

    // MARK: - 文案

    public void NotifyChanged() => StateChanged?.Invoke();

    /// <summary>切换某一行的重置时间显示模式（时间点 ↔ 倒计时），按行独立</summary>
    public void ToggleCountdown(string key)
    {
        if (!CountdownRows.Remove(key)) CountdownRows.Add(key);
    }

    private bool IsCountdown(string key) => CountdownRows.Contains(key);

    /// <summary>5 小时窗口副标题：默认显示重置时间点，点击切换为倒计时</summary>
    public string FiveHourSubtitle(QuotaWindow? window, string key)
    {
        if (window?.ResetDate is not { } date) return "";
        if (IsCountdown(key)) return CountdownText(date);
        var local = date.ToLocalTime();
        var time = local.ToString("HH:mm");
        var today = DateTime.Today;
        if (local.Date == today) return $"今日 {time} 重置";
        if (local.Date == today.AddDays(1)) return $"明日 {time} 重置";
        return $"{local:M月d日} {time} 重置";
    }

    /// <summary>每周窗口副标题：默认显示倒计时，点击切换为重置时间点</summary>
    public string WeeklySubtitle(QuotaWindow? window, string key)
    {
        if (window?.ResetDate is not { } date) return "";
        if (IsCountdown(key))
        {
            var local = date.ToLocalTime();
            return $"{local:M月d日 HH:mm} 重置";
        }
        return CountdownText(date);
    }

    private static string CountdownText(DateTime utcDate)
    {
        var interval = Math.Max(0, (long)(utcDate - DateTime.UtcNow).TotalSeconds);
        var days = interval / 86400;
        var hours = interval % 86400 / 3600;
        var minutes = interval % 3600 / 60;
        if (days > 0) return $"{days} 天 {hours} 小时后重置";
        if (hours > 0) return $"{hours} 小时 {minutes} 分后重置";
        return $"{minutes} 分后重置";
    }
}
