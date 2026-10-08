using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - GLM（智谱）
// GET {base}/api/monitor/usage/quota/limit（API Key 鉴权）

internal static class GLMService
{
    public static async Task<ProviderUsage> FetchAsync(string apiKey, string baseUrl)
    {
        var key = apiKey.Trim();
        if (key.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Get, baseUrl + "/api/monitor/usage/quota/limit");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200) throw QuotaServiceError.Http(status);

        var decoded = JsonSerializer.Deserialize<QuotaResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        if (decoded.Success != true || decoded.Data == null)
            throw QuotaServiceError.Api(decoded.Msg ?? "查询失败");
        return Parse(decoded.Data);
    }

    /// <summary>
    /// 按 unit 字段分类窗口（unit 3 = 5 小时，unit 6 = 每周），
    /// 缺失或不识别时按重置时间排序兜底。不能用时间排序代替 unit——
    /// 周期末尾每周窗口可能比 5 小时窗口更早重置。
    /// </summary>
    private static ProviderUsage Parse(QuotaData quota)
    {
        UsageLimit? fiveHour = null;
        UsageLimit? weekly = null;
        var unclassified = new List<UsageLimit>();

        foreach (var item in quota.Limits ?? new List<UsageLimit>())
        {
            var type = item.Type?.ToLowerInvariant() ?? "";
            if (type != "tokens_limit" && type != "credit_limit") continue;
            switch (item.Unit)
            {
                case 3 when fiveHour == null: fiveHour = item; break;
                case 6 when weekly == null: weekly = item; break;
                default: unclassified.Add(item); break;
            }
        }

        unclassified.Sort((a, b) => (a.NextResetTime ?? long.MinValue).CompareTo(b.NextResetTime ?? long.MinValue));
        foreach (var item in unclassified)
        {
            if (fiveHour == null) fiveHour = item;
            else if (weekly == null) weekly = item;
        }

        var mcp = quota.Limits?.FirstOrDefault(i =>
            string.Equals(i.Type, "TIME_LIMIT", StringComparison.OrdinalIgnoreCase));

        McpUsage? mcpUsage = null;
        if (mcp is { CurrentValue: not null, Usage: not null })
        {
            var total = mcp.Usage.Value;
            mcpUsage = new McpUsage
            {
                Used = mcp.CurrentValue.Value,
                Total = total,
                Remaining = mcp.Remaining ?? Math.Max(0, total - mcp.CurrentValue.Value),
            };
        }

        return new ProviderUsage
        {
            FiveHour = fiveHour?.ToWindow(),
            Weekly = weekly?.ToWindow(),
            Mcp = mcpUsage,
            Level = quota.Level,
        };
    }
}

// MARK: - GLM 响应模型

internal sealed class QuotaResponse
{
    [JsonPropertyName("code")] public int? Code { get; set; }
    [JsonPropertyName("msg")] public string? Msg { get; set; }
    [JsonPropertyName("success")] public bool? Success { get; set; }
    [JsonPropertyName("data")] public QuotaData? Data { get; set; }
}

internal sealed class QuotaData
{
    [JsonPropertyName("limits")] public List<UsageLimit>? Limits { get; set; }
    [JsonPropertyName("level")] public string? Level { get; set; }
}

/// <summary>
/// GLM 单个限额项。
/// TOKENS_LIMIT / CREDIT_LIMIT: token 额度，unit 3 = 5 小时窗口，unit 6 = 每周窗口
/// TIME_LIMIT: MCP 每月调用次数（usage 总量 / currentValue 已用 / remaining 剩余）
/// </summary>
internal sealed class UsageLimit
{
    [JsonPropertyName("type")] public string? Type { get; set; }
    [JsonPropertyName("unit")] public int? Unit { get; set; }
    [JsonPropertyName("number")] public int? Number { get; set; }
    [JsonPropertyName("usage")] public int? Usage { get; set; }
    [JsonPropertyName("currentValue")] public int? CurrentValue { get; set; }
    [JsonPropertyName("remaining")] public int? Remaining { get; set; }
    [JsonPropertyName("percentage")] public double? Percentage { get; set; }
    /// <summary>毫秒时间戳</summary>
    [JsonPropertyName("nextResetTime")] public long? NextResetTime { get; set; }

    public DateTime? ResetDate => NextResetTime is > 0
        ? DateTimeOffset.FromUnixTimeMilliseconds(NextResetTime.Value).UtcDateTime
        : null;

    public QuotaWindow ToWindow() => new() { Percentage = Percentage ?? 0, ResetDate = ResetDate };
}
