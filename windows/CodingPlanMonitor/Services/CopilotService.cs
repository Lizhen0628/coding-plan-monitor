using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - GitHub Copilot（Premium 请求额度）
// GET https://api.github.com/copilot_internal/user
// 凭证：GitHub OAuth Token（gho_…，Copilot CLI/IDE 插件登录后生成，
// 存放于 ~/.config/github-copilot/hosts.json）。
// 返回 quota_snapshots.premium_interactions（每月高级请求额度）等。

internal static class CopilotService
{
    public static async Task<ProviderUsage> FetchAsync(string oauthToken)
    {
        var token = oauthToken.Trim();
        if (token.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/copilot_internal/user");
        request.Headers.Authorization = new AuthenticationHeaderValue("token", token);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        request.Headers.TryAddWithoutValidation("Editor-Version", "vscode/1.96.2");
        request.Headers.TryAddWithoutValidation("Editor-Plugin-Version", "copilot-chat/0.26.7");
        request.Headers.TryAddWithoutValidation("User-Agent", "GitHubCopilotChat/0.26.7");
        request.Headers.TryAddWithoutValidation("X-Github-Api-Version", "2025-04-01");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200)
        {
            if (status is 401 or 403)
                throw QuotaServiceError.Api("Token 无效或已过期，请重新导入或粘贴");
            throw QuotaServiceError.Http(status);
        }

        var decoded = JsonSerializer.Deserialize<CopilotUsageResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        var snapshot = decoded.QuotaSnapshots?.PremiumInteractions ?? decoded.QuotaSnapshots?.Chat;
        if (snapshot == null)
            throw QuotaServiceError.Api("未查询到配额数据，请确认账号有 Copilot 订阅");
        if (snapshot.Unlimited == true)
            throw QuotaServiceError.Api("当前订阅为无限额度，无需监控");

        double used = 0;
        if (snapshot.Entitlement is > 0 && snapshot.Remaining is { } remaining)
            used = (snapshot.Entitlement.Value - remaining) / snapshot.Entitlement.Value * 100;
        else if (snapshot.PercentRemaining is { } percentRemaining)
            used = 100 - percentRemaining;

        return new ProviderUsage
        {
            Monthly = new QuotaWindow
            {
                Percentage = used,
                ResetDate = ParseResetDate(decoded.QuotaResetDate),
            },
            Level = decoded.CopilotPlan,
        };
    }

    /// <summary>quota_reset_date 兼容 "2025-07-01" 与 ISO8601 日期时间</summary>
    private static DateTime? ParseResetDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return TimeHelper.ParseIso(value.Trim());
    }
}

internal sealed class CopilotUsageResponse
{
    internal sealed class QuotaSnapshots
    {
        internal sealed class Snapshot
        {
            [JsonPropertyName("entitlement")] public double? Entitlement { get; set; }
            [JsonPropertyName("remaining")] public double? Remaining { get; set; }
            [JsonPropertyName("percent_remaining")] public double? PercentRemaining { get; set; }
            [JsonPropertyName("unlimited")] public bool? Unlimited { get; set; }
        }

        [JsonPropertyName("premium_interactions")] public Snapshot? PremiumInteractions { get; set; }
        [JsonPropertyName("chat")] public Snapshot? Chat { get; set; }
    }

    [JsonPropertyName("quota_snapshots")] public QuotaSnapshots? QuotaSnapshots { get; set; }
    [JsonPropertyName("copilot_plan")] public string? CopilotPlan { get; set; }
    [JsonPropertyName("quota_reset_date")] public string? QuotaResetDate { get; set; }
}
