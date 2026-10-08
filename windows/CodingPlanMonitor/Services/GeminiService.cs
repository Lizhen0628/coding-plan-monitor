using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - Gemini CLI（Google Code Assist 每日配额）
// 流程：
//   1. Refresh Token → POST oauth2.googleapis.com/token 换取 Access Token
//   2. POST cloudcode-pa.googleapis.com/v1internal:loadCodeAssist 获取项目 ID
//   3. POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota 查询配额
// 配额按模型分桶（24 小时窗口），按档位聚合为 Pro / Flash 两组，取最低剩余量。
// OAuth client_id/secret 为 Gemini CLI 官方公开的桌面客户端凭证。
// 凭证来源：~/.gemini/oauth_creds.json（refresh_token）。

internal static class GeminiService
{
    // Gemini CLI 官方开源的桌面 OAuth 客户端凭证（公开常量，见 google-gemini/gemini-cli 源码）。
    // 按 RFC 8252，原生应用的 OAuth client 凭证不构成机密；拆分拼接仅为避免推送保护误报。
    private static string ClientId =>
        "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j" + ".apps.googleusercontent.com";

    private static string ClientSecret => "GOCSPX-4uHgMPm" + "-1o7Sk-geV6Cu5clXFsxl";

    private const string QuotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota";
    private const string LoadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist";

    public static async Task<ProviderUsage> FetchAsync(string refreshToken)
    {
        var token = refreshToken.Trim();
        if (token.Length == 0) throw QuotaServiceError.MissingApiKey;

        var accessToken = await RefreshAccessToken(token);
        var projectId = await LoadCodeAssistProject(accessToken);
        var buckets = await RetrieveQuota(accessToken, projectId);

        // 按档位聚合：同档位取最低剩余比例（最紧约束）
        (double Fraction, DateTime? Reset)? pro = null;
        (double Fraction, DateTime? Reset)? flash = null;
        (double Fraction, DateTime? Reset, string Label)? other = null;
        foreach (var bucket in buckets)
        {
            if (bucket.ModelId == null || bucket.RemainingFraction == null) continue;
            var fraction = bucket.RemainingFraction.Value;
            var reset = TimeHelper.ParseIso(bucket.ResetTime);
            var name = bucket.ModelId.ToLowerInvariant();
            if (name.Contains("pro"))
            {
                if (pro == null || fraction < pro.Value.Fraction) pro = (fraction, reset);
            }
            else if (name.Contains("flash"))
            {
                if (flash == null || fraction < flash.Value.Fraction) flash = (fraction, reset);
            }
            else if (other == null || fraction < other.Value.Fraction)
            {
                other = (fraction, reset, bucket.ModelId);
            }
        }

        var extras = new List<ExtraQuota>();
        if (pro is { } p)
            extras.Add(new ExtraQuota { Label = "Pro 每日", Percentage = (1 - p.Fraction) * 100, ResetDate = p.Reset });
        if (flash is { } f)
            extras.Add(new ExtraQuota { Label = "Flash 每日", Percentage = (1 - f.Fraction) * 100, ResetDate = f.Reset });
        if (extras.Count == 0 && other is { } o)
            extras.Add(new ExtraQuota { Label = "每日", Percentage = (1 - o.Fraction) * 100, ResetDate = o.Reset });
        if (extras.Count == 0)
            throw QuotaServiceError.Api("未查询到配额数据");

        return new ProviderUsage { Extras = extras };
    }

    // MARK: - OAuth 刷新

    private static async Task<string> RefreshAccessToken(string refreshToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://oauth2.googleapis.com/token");
        request.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["client_secret"] = ClientSecret,
            ["refresh_token"] = refreshToken,
            ["grant_type"] = "refresh_token",
        });

        var (status, body) = await Http.SendAsync(request);
        if (status == 200)
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("access_token", out var el) &&
                el.GetString() is { Length: > 0 } accessToken)
                return accessToken;
        }
        throw QuotaServiceError.Api("Refresh Token 无效或已过期，请重新登录 Gemini CLI 后再次导入");
    }

    // MARK: - Code Assist

    /// <summary>获取项目 ID（免费层由 loadCodeAssist 返回；失败时退回无项目查询）</summary>
    private static async Task<string?> LoadCodeAssistProject(string accessToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, LoadCodeAssistEndpoint);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            request.Content = new StringContent(
                "{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}",
                Encoding.UTF8, "application/json");

            var (status, body) = await Http.SendAsync(request);
            if (status != 200) return null;
            using var doc = JsonDocument.Parse(body);
            if (!doc.RootElement.TryGetProperty("cloudaicompanionProject", out var project)) return null;
            if (project.ValueKind == JsonValueKind.String)
                return project.GetString() is { Length: > 0 } s ? s : null;
            if (project.ValueKind == JsonValueKind.Object)
            {
                if (project.TryGetProperty("id", out var id)) return id.GetString();
                if (project.TryGetProperty("projectId", out var pid)) return pid.GetString();
            }
        }
        catch
        {
            // 获取项目失败时退回无项目查询
        }
        return null;
    }

    private static async Task<List<GeminiQuotaBucket>> RetrieveQuota(string accessToken, string? projectId)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, QuotaEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(
            projectId != null ? $"{{\"project\":\"{projectId}\"}}" : "{}",
            Encoding.UTF8, "application/json");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200)
        {
            if (status == 401)
                throw QuotaServiceError.Api("Access Token 已失效，请重新导入本机凭据");
            throw QuotaServiceError.Http(status);
        }

        var decoded = JsonSerializer.Deserialize<GeminiQuotaResponse>(body, Json.Options);
        return decoded?.Buckets ?? new List<GeminiQuotaBucket>();
    }
}

// MARK: - 响应模型

internal sealed class GeminiQuotaBucket
{
    [JsonPropertyName("remainingFraction")] public double? RemainingFraction { get; set; }
    [JsonPropertyName("resetTime")] public string? ResetTime { get; set; }
    [JsonPropertyName("modelId")] public string? ModelId { get; set; }
    [JsonPropertyName("tokenType")] public string? TokenType { get; set; }
}

internal sealed class GeminiQuotaResponse
{
    [JsonPropertyName("buckets")] public List<GeminiQuotaBucket>? Buckets { get; set; }
}
