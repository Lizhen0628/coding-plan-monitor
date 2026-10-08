using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - Kimi（月之暗面）
// GET https://api.kimi.com/coding/v1/usages（sk-kimi- API Key 鉴权）
// 注意：该接口的数值字段（used/limit/remaining）以字符串形式返回。

internal static class KimiService
{
    public static async Task<ProviderUsage> FetchAsync(string apiKey)
    {
        var key = apiKey.Trim();
        if (key.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.kimi.com/coding/v1/usages");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200) throw QuotaServiceError.Http(status);

        var decoded = JsonSerializer.Deserialize<KimiUsagesResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;

        // 5 小时窗口按 window 元数据识别（300 分钟），兜底取第一个窗口
        var fiveHourItem = decoded.Limits?.FirstOrDefault(l =>
                               l.Window?.Duration == 300 && l.Window?.TimeUnit == "TIME_UNIT_MINUTE")
                           ?? decoded.Limits?.FirstOrDefault();
        var fiveHour = fiveHourItem?.Detail?.ToWindow();
        var weekly = decoded.Usage?.ToWindow();
        if (fiveHour == null && weekly == null) throw QuotaServiceError.InvalidResponse;

        // totalQuota 可能为空对象（未开通每月额度时不返回数据），limit 缺失则视为无
        QuotaWindow? monthly = null;
        if (decoded.TotalQuota is { } totalQuota && (totalQuota.Limit ?? 0) > 0)
            monthly = totalQuota.ToWindow();

        return new ProviderUsage
        {
            FiveHour = fiveHour,
            Weekly = weekly,
            Monthly = monthly,
            Level = NormalizeLevel(decoded.User?.Membership?.Level),
        };
    }

    /// <summary>"LEVEL_INTERMEDIATE" → "intermediate"</summary>
    private static string? NormalizeLevel(string? level)
    {
        if (string.IsNullOrEmpty(level)) return null;
        return Regex.Replace(level, @"^LEVEL[_ ]", "").ToLowerInvariant();
    }
}

// MARK: - Kimi 响应模型

internal sealed class KimiUsagesResponse
{
    internal sealed class Detail
    {
        [JsonPropertyName("used"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? Used { get; set; }

        [JsonPropertyName("limit"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? Limit { get; set; }

        [JsonPropertyName("remaining"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? Remaining { get; set; }

        [JsonPropertyName("resetTime"), JsonConverter(typeof(FlexibleDateConverter))]
        public DateTime? ResetTime { get; set; }

        public QuotaWindow ToWindow()
        {
            var limit = Limit ?? 0;
            var used = Used ?? Math.Max(0, limit - (Remaining ?? 0));
            return new QuotaWindow
            {
                Percentage = limit > 0 ? used / limit * 100 : 0,
                ResetDate = ResetTime,
            };
        }
    }

    internal sealed class LimitItem
    {
        internal sealed class WindowInfo
        {
            /// <summary>分钟数，5 小时窗口为 300</summary>
            [JsonPropertyName("duration")] public int? Duration { get; set; }
            [JsonPropertyName("timeUnit")] public string? TimeUnit { get; set; }
        }

        [JsonPropertyName("window")] public WindowInfo? Window { get; set; }
        [JsonPropertyName("detail")] public Detail? Detail { get; set; }
    }

    internal sealed class TotalQuota
    {
        [JsonPropertyName("limit"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? Limit { get; set; }

        [JsonPropertyName("remaining"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? Remaining { get; set; }

        public QuotaWindow ToWindow()
        {
            var limit = Limit ?? 0;
            var used = Math.Max(0, limit - (Remaining ?? 0));
            return new QuotaWindow { Percentage = limit > 0 ? used / limit * 100 : 0 };
        }
    }

    internal sealed class UserInfo
    {
        internal sealed class Membership
        {
            /// <summary>如 "LEVEL_INTERMEDIATE"</summary>
            [JsonPropertyName("level")] public string? Level { get; set; }
        }

        [JsonPropertyName("membership")] public Membership? Membership { get; set; }
    }

    [JsonPropertyName("user")] public UserInfo? User { get; set; }
    /// <summary>每周额度</summary>
    [JsonPropertyName("usage")] public Detail? Usage { get; set; }
    /// <summary>限流窗口列表，含 5 小时窗口</summary>
    [JsonPropertyName("limits")] public List<LimitItem>? Limits { get; set; }
    /// <summary>每月总额度（无重置时间）</summary>
    [JsonPropertyName("totalQuota")] public TotalQuota? TotalQuota { get; set; }
}
