using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - MiniMax Coding Plan
// GET {host}/v1/api/openplatform/coding_plan/remains
// 国内 host: api.minimaxi.com，国际 host: api.minimax.io
// 凭证：开放平台 API Key（Bearer）。
// 注意：响应中的 usage_count 字段实为「剩余」额度。

internal static class MiniMaxService
{
    public static async Task<ProviderUsage> FetchAsync(string apiKey, string region)
    {
        var key = apiKey.Trim();
        if (key.Length == 0) throw QuotaServiceError.MissingApiKey;
        var host = region == "intl" ? "https://api.minimax.io" : "https://api.minimaxi.com";

        using var request = new HttpRequestMessage(HttpMethod.Get,
            host + "/v1/api/openplatform/coding_plan/remains");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200) throw QuotaServiceError.Http(status);

        var decoded = JsonSerializer.Deserialize<MiniMaxRemainsResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        var baseResp = decoded.Data?.BaseResp ?? decoded.BaseResp;
        if (baseResp?.StatusCode is { } code && code != 0)
        {
            var message = baseResp.StatusMsg ?? $"错误码 {code}";
            if (code == 1004 || message.ToLowerInvariant().Contains("login"))
                throw QuotaServiceError.Api("API Key 无效或区域不匹配，请检查凭证与区域设置");
            throw QuotaServiceError.Api(message);
        }

        // 多模型时取第一个有窗口数据的条目
        var model = decoded.Data?.ModelRemains?.FirstOrDefault(m => (m.CurrentIntervalTotalCount ?? 0) > 0)
                    ?? decoded.Data?.ModelRemains?.FirstOrDefault();
        if (model == null)
            throw QuotaServiceError.Api("未查询到用量数据，请确认已订阅 Coding Plan");

        return new ProviderUsage
        {
            FiveHour = Window(model.CurrentIntervalTotalCount, model.CurrentIntervalUsageCount,
                model.CurrentIntervalRemainingPercent, model.EndTime),
            Weekly = Window(model.CurrentWeeklyTotalCount, model.CurrentWeeklyUsageCount,
                model.CurrentWeeklyRemainingPercent, model.WeeklyEndTime),
            Level = model.ModelName,
        };
    }

    /// <summary>usage_count 为剩余额度；优先用 total/remaining 计算，兜底用 remaining_percent</summary>
    private static QuotaWindow? Window(double? total, double? remaining, double? remainingPercent, double? reset)
    {
        double? used = null;
        if (total is > 0 && remaining is { } rem)
            used = (total.Value - rem) / total.Value * 100;
        else if (remainingPercent is { } rp)
            used = 100 - rp;
        if (used == null) return null;
        return new QuotaWindow { Percentage = used.Value, ResetDate = DateFrom(reset) };
    }

    /// <summary>时间戳兼容秒/毫秒</summary>
    private static DateTime? DateFrom(double? value) =>
        value is > 1_000_000_000 ? TimeHelper.FromEpoch(value.Value) : null;
}

// MARK: - 响应模型

internal sealed class MiniMaxRemainsResponse
{
    internal sealed class BaseResp
    {
        [JsonPropertyName("status_code")] public int? StatusCode { get; set; }
        [JsonPropertyName("status_msg")] public string? StatusMsg { get; set; }
    }

    internal sealed class ModelRemains
    {
        [JsonPropertyName("model_name")] public string? ModelName { get; set; }

        [JsonPropertyName("current_interval_total_count"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? CurrentIntervalTotalCount { get; set; }

        /// <summary>注意：字段名叫 usage_count，但实际值是「剩余」额度</summary>
        [JsonPropertyName("current_interval_usage_count"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? CurrentIntervalUsageCount { get; set; }

        [JsonPropertyName("current_interval_remaining_percent"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? CurrentIntervalRemainingPercent { get; set; }

        [JsonPropertyName("end_time"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? EndTime { get; set; }

        [JsonPropertyName("current_weekly_total_count"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? CurrentWeeklyTotalCount { get; set; }

        [JsonPropertyName("current_weekly_usage_count"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? CurrentWeeklyUsageCount { get; set; }

        [JsonPropertyName("current_weekly_remaining_percent"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? CurrentWeeklyRemainingPercent { get; set; }

        [JsonPropertyName("weekly_end_time"), JsonConverter(typeof(FlexibleDoubleConverter))]
        public double? WeeklyEndTime { get; set; }
    }

    internal sealed class Payload
    {
        [JsonPropertyName("model_remains")] public List<ModelRemains>? ModelRemains { get; set; }
        [JsonPropertyName("base_resp")] public BaseResp? BaseResp { get; set; }
    }

    [JsonPropertyName("data")] public Payload? Data { get; set; }
    [JsonPropertyName("base_resp")] public BaseResp? BaseResp { get; set; }
}
