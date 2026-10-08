using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - 通义（阿里云百炼 Coding Plan）
// POST {console}/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2
// 凭证为 Coding Plan 专用 API Key（sk-sp-…）。

internal static class AlibabaService
{
    public static async Task<ProviderUsage> FetchAsync(string apiKey, string region)
    {
        var key = apiKey.Trim();
        if (key.Length == 0) throw QuotaServiceError.MissingApiKey;

        var isCN = region != "intl";
        var baseUrl = isCN ? "https://bailian.console.aliyun.com" : "https://modelstudio.console.alibabacloud.com";
        var url = baseUrl + "/data/api.json"
            + "?action=" + Uri.EscapeDataString("zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2")
            + "&product=broadscope-bailian"
            + "&api=queryCodingPlanInstanceInfoV2"
            + "&currentRegionId=" + (isCN ? "cn-beijing" : "ap-southeast-1");

        var bodyJson = JsonSerializer.Serialize(new
        {
            queryCodingPlanInstanceInfoRequest = new
            {
                commodityCode = isCN ? "sfm_codingplan_public_cn" : "sfm_codingplan_public_intl",
            },
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Content = new StringContent(bodyJson, Encoding.UTF8, "application/json");
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {key}");
        request.Headers.TryAddWithoutValidation("x-api-key", key);
        request.Headers.TryAddWithoutValidation("X-DashScope-API-Key", key);
        request.Headers.TryAddWithoutValidation("User-Agent",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36");
        request.Headers.TryAddWithoutValidation("Origin", baseUrl);
        request.Headers.TryAddWithoutValidation("Referer", isCN
            ? "https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan"
            : "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200) throw QuotaServiceError.Http(status);
        return Parse(body);
    }

    /// <summary>响应为控制台网关结构，quota 字段嵌套层级不固定，用深度搜索兜底</summary>
    internal static ProviderUsage Parse(string body)
    {
        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;

        // 错误检测：ConsoleNeedLogin / 非 0/200 状态码
        var codeText = (DeepFindString(root, "code", "status", "statusCode") ?? "").ToLowerInvariant();
        var messageText = DeepFindString(root, "message", "msg", "statusMessage") ?? "";
        if (codeText.Contains("needlogin") || messageText.ToLowerInvariant().Contains("console session"))
            throw QuotaServiceError.Api("该账号当前区域不支持 API Key 查询，请到设置中切换区域");
        if (DeepFindLong(root, "statusCode", "status_code") is { } codeInt && codeInt != 0 && codeInt != 200)
            throw QuotaServiceError.Api(messageText.Length == 0 ? $"查询失败（{codeInt}）" : messageText);

        var quota = DeepFindDict(root,
            "per5HourUsedQuota", "per5HourTotalQuota",
            "perWeekUsedQuota", "perWeekTotalQuota",
            "perBillMonthUsedQuota", "perBillMonthTotalQuota");
        if (quota == null)
            throw QuotaServiceError.Api("未查询到用量数据，请确认账号已开通 Coding Plan");

        var planName = DeepFindString(root, "planName", "instanceName", "packageName");

        return new ProviderUsage
        {
            FiveHour = Window(quota.Value,
                new[] { "per5HourUsedQuota", "perFiveHourUsedQuota" },
                new[] { "per5HourTotalQuota", "perFiveHourTotalQuota" },
                new[] { "per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime" }),
            Weekly = Window(quota.Value,
                new[] { "perWeekUsedQuota" },
                new[] { "perWeekTotalQuota" },
                new[] { "perWeekQuotaNextRefreshTime" }),
            Monthly = Window(quota.Value,
                new[] { "perBillMonthUsedQuota", "perMonthUsedQuota" },
                new[] { "perBillMonthTotalQuota", "perMonthTotalQuota" },
                new[] { "perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime" }),
            Level = planName,
        };
    }

    private static QuotaWindow? Window(JsonElement quota, string[] usedKeys, string[] totalKeys, string[] resetKeys)
    {
        var total = IntValue(quota, totalKeys);
        if (total is not > 0) return null;
        var used = IntValue(quota, usedKeys) ?? 0;
        return new QuotaWindow
        {
            Percentage = Math.Min(100, (double)used / total.Value * 100),
            ResetDate = DateValue(quota, resetKeys),
        };
    }

    // MARK: 深度搜索辅助

    private static JsonElement? DeepFindDict(JsonElement el, params string[] keys)
    {
        if (el.ValueKind == JsonValueKind.Object)
        {
            foreach (var key in keys)
                if (el.TryGetProperty(key, out _))
                    return el;
            foreach (var prop in el.EnumerateObject())
                if (DeepFindDict(prop.Value, keys) is { } found)
                    return found;
        }
        else if (el.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in el.EnumerateArray())
                if (DeepFindDict(item, keys) is { } found)
                    return found;
        }
        return null;
    }

    private static string? DeepFindString(JsonElement el, params string[] keys)
    {
        if (el.ValueKind == JsonValueKind.Object)
        {
            foreach (var key in keys)
                if (el.TryGetProperty(key, out var v) &&
                    v.ValueKind == JsonValueKind.String &&
                    v.GetString() is { Length: > 0 } s)
                    return s;
            foreach (var prop in el.EnumerateObject())
                if (DeepFindString(prop.Value, keys) is { } found)
                    return found;
        }
        else if (el.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in el.EnumerateArray())
                if (DeepFindString(item, keys) is { } found)
                    return found;
        }
        return null;
    }

    private static long? DeepFindLong(JsonElement el, params string[] keys)
    {
        if (el.ValueKind == JsonValueKind.Object)
        {
            foreach (var key in keys)
                if (el.TryGetProperty(key, out var v))
                {
                    if (v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n)) return n;
                    if (v.ValueKind == JsonValueKind.String &&
                        long.TryParse(v.GetString(), out var parsed)) return parsed;
                }
            foreach (var prop in el.EnumerateObject())
                if (DeepFindLong(prop.Value, keys) is { } found)
                    return found;
        }
        else if (el.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in el.EnumerateArray())
                if (DeepFindLong(item, keys) is { } found)
                    return found;
        }
        return null;
    }

    private static long? IntValue(JsonElement dict, string[] keys)
    {
        if (dict.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in keys)
        {
            if (!dict.TryGetProperty(key, out var v)) continue;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n)) return n;
            if (v.ValueKind == JsonValueKind.String && long.TryParse(v.GetString(), out var parsed)) return parsed;
        }
        return null;
    }

    /// <summary>兼容秒/毫秒时间戳与 ISO8601 字符串</summary>
    private static DateTime? DateValue(JsonElement dict, string[] keys)
    {
        if (dict.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in keys)
        {
            if (!dict.TryGetProperty(key, out var v)) continue;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var num) && num > 0)
                return TimeHelper.FromEpoch(num);
            if (v.ValueKind == JsonValueKind.String)
            {
                var text = v.GetString();
                if (TimeHelper.ParseIso(text) is { } date) return date;
                if (double.TryParse(text, out var num2) && num2 > 0)
                    return TimeHelper.FromEpoch(num2);
            }
        }
        return null;
    }
}
