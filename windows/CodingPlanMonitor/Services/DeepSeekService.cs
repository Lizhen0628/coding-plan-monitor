using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - DeepSeek（按量计费账户余额）
// GET https://api.deepseek.com/user/balance
// 凭证：开放平台 API Key（sk-…）。
// 返回人民币/美元余额（含赠送额度），数值字段以字符串形式返回。

internal static class DeepSeekService
{
    public static async Task<ProviderUsage> FetchAsync(string apiKey)
    {
        var key = apiKey.Trim();
        if (key.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.deepseek.com/user/balance");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");

        var (status, body) = await Http.SendAsync(request);
        if (status != 200) throw QuotaServiceError.Http(status);

        var decoded = JsonSerializer.Deserialize<DeepSeekBalanceResponse>(body, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        var info = decoded.BalanceInfos?.FirstOrDefault();
        if (info == null ||
            !double.TryParse(info.TotalBalance, NumberStyles.Any, CultureInfo.InvariantCulture, out var total))
            throw QuotaServiceError.InvalidResponse;

        double.TryParse(info.GrantedBalance, NumberStyles.Any, CultureInfo.InvariantCulture, out var granted);
        return new ProviderUsage
        {
            Level = decoded.IsAvailable == false ? "余额不足" : null,
            Balance = new BalanceInfo
            {
                Total = total,
                Granted = granted,
                Currency = info.Currency ?? "CNY",
            },
        };
    }
}

internal sealed class DeepSeekBalanceResponse
{
    internal sealed class Info
    {
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("total_balance")] public string? TotalBalance { get; set; }
        [JsonPropertyName("granted_balance")] public string? GrantedBalance { get; set; }
        [JsonPropertyName("topped_up_balance")] public string? ToppedUpBalance { get; set; }
    }

    [JsonPropertyName("is_available")] public bool? IsAvailable { get; set; }
    [JsonPropertyName("balance_infos")] public List<Info>? BalanceInfos { get; set; }
}
