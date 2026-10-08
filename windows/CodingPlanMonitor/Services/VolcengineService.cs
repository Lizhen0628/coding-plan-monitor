using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

// MARK: - 火山引擎（Volcengine Coding Plan）
// POST https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01
// 使用火山 V4 HMAC-SHA256 签名（service: ark），凭证为 AK/SK 对。

internal static class VolcengineService
{
    public static async Task<ProviderUsage> FetchAsync(string accessKey, string secretKey)
    {
        var ak = accessKey.Trim();
        var sk = secretKey.Trim();
        if (ak.Length == 0 || sk.Length == 0) throw QuotaServiceError.MissingApiKey;

        using var request = new HttpRequestMessage(HttpMethod.Post,
            "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01");
        var body = Array.Empty<byte>();
        var content = new ByteArrayContent(body);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json") { CharSet = "utf-8" };
        request.Content = content;
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        VolcengineSigner.Sign(request, body, ak, sk);

        var (status, responseBody) = await Http.SendAsync(request);
        if (status != 200) throw QuotaServiceError.Http(status);

        var decoded = JsonSerializer.Deserialize<VolcUsageResponse>(responseBody, Json.Options)
                      ?? throw QuotaServiceError.InvalidResponse;
        if (!string.IsNullOrEmpty(decoded.ResponseMetadata?.Error?.Message))
            throw QuotaServiceError.Api(decoded.ResponseMetadata.Error.Message);
        if (decoded.Result == null) throw QuotaServiceError.InvalidResponse;

        QuotaWindow? fiveHour = null;
        QuotaWindow? weekly = null;
        QuotaWindow? monthly = null;
        foreach (var quota in decoded.Result.QuotaUsage ?? new List<VolcUsageResponse.Quota>())
        {
            var window = new QuotaWindow
            {
                Percentage = NormalizePercent(quota.Percent),
                ResetDate = quota.ResetTimestamp is > 0
                    ? DateTimeOffset.FromUnixTimeSeconds((long)quota.ResetTimestamp.Value).UtcDateTime
                    : null,
            };
            var level = quota.Level?.ToLowerInvariant() ?? "";
            if (level.Contains("session") || level.Contains("5h") || level.Contains("5-hour") || level.Contains("five"))
                fiveHour ??= window;
            else if (level.Contains("week"))
                weekly ??= window;
            else if (level.Contains("month"))
                monthly ??= window;
            else
                fiveHour ??= window;
        }
        if (fiveHour == null && weekly == null && monthly == null)
            throw QuotaServiceError.Api("未查询到用量数据，请确认账号已开通 Coding Plan");

        return new ProviderUsage { FiveHour = fiveHour, Weekly = weekly, Monthly = monthly };
    }

    /// <summary>Percent 可能是 0~1 小数或 0~100 数值</summary>
    private static double NormalizePercent(double? value) =>
        value is not { } v ? 0 : v <= 1 ? v * 100 : v;
}

internal sealed class VolcUsageResponse
{
    internal sealed class Quota
    {
        [JsonPropertyName("Level")] public string? Level { get; set; }
        [JsonPropertyName("Percent")] public double? Percent { get; set; }
        /// <summary>秒级时间戳</summary>
        [JsonPropertyName("ResetTimestamp")] public double? ResetTimestamp { get; set; }
    }

    internal sealed class ResultPayload
    {
        [JsonPropertyName("QuotaUsage")] public List<Quota>? QuotaUsage { get; set; }
    }

    internal sealed class Metadata
    {
        internal sealed class ErrorPayload
        {
            [JsonPropertyName("Message")] public string? Message { get; set; }
        }

        [JsonPropertyName("Error")] public ErrorPayload? Error { get; set; }
    }

    [JsonPropertyName("Result")] public ResultPayload? Result { get; set; }
    [JsonPropertyName("ResponseMetadata")] public Metadata? ResponseMetadata { get; set; }
}

/// <summary>火山 V4 HMAC-SHA256 签名</summary>
internal static class VolcengineSigner
{
    public static void Sign(HttpRequestMessage request, byte[] body, string accessKey, string secretKey,
        string region = "cn-beijing")
    {
        var now = DateTime.UtcNow;
        var timestamp = now.ToString("yyyyMMdd'T'HHmmss'Z'", CultureInfo.InvariantCulture);
        var dateStamp = now.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        var payloadHash = Sha256Hex(body);
        const string contentType = "application/json; charset=utf-8";
        var host = request.RequestUri?.Host ?? "open.volcengineapi.com";
        const string signedHeaders = "content-type;host;x-content-sha256;x-date";

        request.Headers.TryAddWithoutValidation("X-Date", timestamp);
        request.Headers.TryAddWithoutValidation("X-Content-Sha256", payloadHash);

        var canonicalRequest = string.Join("\n", new[]
        {
            request.Method.Method,
            "/",
            CanonicalQueryString(request.RequestUri),
            $"content-type:{contentType}",
            $"host:{host}",
            $"x-content-sha256:{payloadHash}",
            $"x-date:{timestamp}",
            "",
            signedHeaders,
            payloadHash,
        });

        var credentialScope = $"{dateStamp}/{region}/ark/request";
        var stringToSign = string.Join("\n", new[]
        {
            "HMAC-SHA256",
            timestamp,
            credentialScope,
            Sha256Hex(Encoding.UTF8.GetBytes(canonicalRequest)),
        });

        var dateKey = Hmac(Encoding.UTF8.GetBytes(secretKey), dateStamp);
        var regionKey = Hmac(dateKey, region);
        var serviceKey = Hmac(regionKey, "ark");
        var signingKey = Hmac(serviceKey, "request");
        var signature = ToHex(Hmac(signingKey, stringToSign));

        request.Headers.TryAddWithoutValidation("Authorization",
            $"HMAC-SHA256 Credential={accessKey}/{credentialScope}, SignedHeaders={signedHeaders}, Signature={signature}");
    }

    private static string CanonicalQueryString(Uri? uri)
    {
        var query = uri?.Query;
        if (string.IsNullOrEmpty(query)) return "";
        var pairs = new List<(string Key, string Value)>();
        foreach (var part in query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var idx = part.IndexOf('=');
            var name = idx >= 0 ? part[..idx] : part;
            var value = idx >= 0 ? part[(idx + 1)..] : "";
            pairs.Add((PercentEncode(name), PercentEncode(value)));
        }
        if (pairs.Count == 0) return "";
        pairs.Sort((a, b) =>
        {
            var cmp = string.CompareOrdinal(a.Key, b.Key);
            return cmp != 0 ? cmp : string.CompareOrdinal(a.Value, b.Value);
        });
        return string.Join("&", pairs.Select(p => $"{p.Key}={p.Value}"));
    }

    /// <summary>RFC 3986：仅保留 unreserved 字符，其余按 UTF-8 大写百分号编码</summary>
    private static string PercentEncode(string value)
    {
        var sb = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes(value))
        {
            var c = (char)b;
            if (c is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9'
                or '-' or '_' or '.' or '~')
                sb.Append(c);
            else
                sb.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }

    private static byte[] Hmac(byte[] key, string message)
    {
        using var hmac = new HMACSHA256(key);
        return hmac.ComputeHash(Encoding.UTF8.GetBytes(message));
    }

    private static string Sha256Hex(byte[] data)
    {
        using var sha = SHA256.Create();
        return ToHex(sha.ComputeHash(data));
    }

    private static string ToHex(byte[] data) => Convert.ToHexString(data).ToLowerInvariant();
}
