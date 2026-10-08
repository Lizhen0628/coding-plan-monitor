using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - Claude（Anthropic Pro/Max 订阅）
// GET https://api.anthropic.com/api/oauth/usage（未公开接口，Claude Code 内部使用）
// 凭证为 Claude Code 的 OAuth Token（sk-ant-oat-…）。

internal static class ClaudeService
{
    public static async Task<ProviderUsage> FetchAsync(string oauthToken)
    {
        var token = oauthToken.Trim();
        if (token.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.anthropic.com/api/oauth/usage");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
        request.Headers.TryAddWithoutValidation("User-Agent", "claude-code/2.1.59");
        request.Headers.TryAddWithoutValidation("Accept", "application/json");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200)
        {
            if (status is 401 or 403)
                throw QuotaServiceError.Api("OAuth Token 无效或已过期，请重新从本机导入");
            throw QuotaServiceError.Http(status);
        }

        var decoded = JsonSerializer.Deserialize<ClaudeUsageResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        if (decoded.FiveHour == null && decoded.SevenDay == null)
            throw QuotaServiceError.InvalidResponse;

        return new ProviderUsage
        {
            FiveHour = decoded.FiveHour?.ToWindow(),
            Weekly = decoded.SevenDay?.ToWindow(),
        };
    }
}

internal sealed class ClaudeUsageResponse
{
    internal sealed class Window
    {
        [JsonPropertyName("utilization")] public double? Utilization { get; set; }

        [JsonPropertyName("resets_at"), JsonConverter(typeof(FlexibleDateConverter))]
        public DateTime? ResetsAt { get; set; }

        public QuotaWindow ToWindow() => new() { Percentage = Utilization ?? 0, ResetDate = ResetsAt };
    }

    [JsonPropertyName("five_hour")] public Window? FiveHour { get; set; }
    [JsonPropertyName("seven_day")] public Window? SevenDay { get; set; }
}
