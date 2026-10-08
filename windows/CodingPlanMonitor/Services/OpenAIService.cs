using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - OpenAI（Codex / ChatGPT 订阅）
// GET https://chatgpt.com/backend-api/wham/usage（Codex CLI 内部接口）
// 凭证为 ~/.codex/auth.json 中的 access_token 与 account_id。

internal static class OpenAIService
{
    public static async Task<ProviderUsage> FetchAsync(string accessToken, string accountId)
    {
        var token = accessToken.Trim();
        if (token.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Get, "https://chatgpt.com/backend-api/wham/usage");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.TryAddWithoutValidation("User-Agent", "codex_cli_rs/0.76.0");
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        var account = accountId.Trim();
        if (account.Length > 0)
            request.Headers.TryAddWithoutValidation("Chatgpt-Account-Id", account);

        var (status, body) = await Http.SendAsync(request);
        if (status != 200)
        {
            if (status is 401 or 403)
                throw QuotaServiceError.Api("Access Token 无效或已过期，请运行 codex 登录后重新导入");
            throw QuotaServiceError.Http(status);
        }

        var decoded = JsonSerializer.Deserialize<CodexUsageResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        var fiveHour = decoded.RateLimit?.PrimaryWindow?.ToWindow();
        var weekly = decoded.RateLimit?.SecondaryWindow?.ToWindow();
        if (fiveHour == null && weekly == null) throw QuotaServiceError.InvalidResponse;

        return new ProviderUsage { FiveHour = fiveHour, Weekly = weekly };
    }
}

internal sealed class CodexUsageResponse
{
    internal sealed class Window
    {
        [JsonPropertyName("used_percent")] public double? UsedPercent { get; set; }
        [JsonPropertyName("reset_after_seconds")] public int? ResetAfterSeconds { get; set; }
        [JsonPropertyName("reset_at")] public long? ResetAt { get; set; }

        public QuotaWindow ToWindow()
        {
            DateTime? reset = null;
            if (ResetAt is > 0)
                reset = DateTimeOffset.FromUnixTimeSeconds(ResetAt.Value).UtcDateTime;
            else if (ResetAfterSeconds is > 0)
                reset = DateTime.UtcNow.AddSeconds(ResetAfterSeconds.Value);
            return new QuotaWindow { Percentage = UsedPercent ?? 0, ResetDate = reset };
        }
    }

    internal sealed class RateLimit
    {
        [JsonPropertyName("primary_window")] public Window? PrimaryWindow { get; set; }
        [JsonPropertyName("secondary_window")] public Window? SecondaryWindow { get; set; }
    }

    [JsonPropertyName("rate_limit")] public RateLimit? RateLimit { get; set; }
}
