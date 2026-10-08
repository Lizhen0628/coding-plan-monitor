using System;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodingPlanMonitor.Services;

/// <summary>数值兼容字符串与 JSON 数字（Kimi 等接口以字符串返回数值）</summary>
internal sealed class FlexibleDoubleConverter : JsonConverter<double?>
{
    public override double? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number && reader.TryGetDouble(out var number))
            return number;
        if (reader.TokenType == JsonTokenType.String &&
            double.TryParse(reader.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var parsed))
            return parsed;
        return null;
    }

    public override void Write(Utf8JsonWriter writer, double? value, JsonSerializerOptions options)
        => throw new NotSupportedException();
}

/// <summary>resetTime 兼容 ISO 8601 字符串与秒/毫秒时间戳</summary>
internal sealed class FlexibleDateConverter : JsonConverter<DateTime?>
{
    public override DateTime? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            var text = reader.GetString();
            if (!string.IsNullOrWhiteSpace(text))
            {
                if (DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dto))
                    return dto.UtcDateTime;
                if (double.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out var num) && num > 0)
                    return TimeHelper.FromEpoch(num);
            }
            return null;
        }
        if (reader.TokenType == JsonTokenType.Number && reader.TryGetInt64(out var number))
            return number > 0 ? TimeHelper.FromEpoch(number) : null;
        return null;
    }

    public override void Write(Utf8JsonWriter writer, DateTime? value, JsonSerializerOptions options)
        => throw new NotSupportedException();
}

internal static class TimeHelper
{
    /// <summary>秒级时间戳 &lt; 1e12，毫秒 &gt;= 1e12</summary>
    public static DateTime FromEpoch(double raw) => raw >= 1_000_000_000_000
        ? DateTimeOffset.FromUnixTimeMilliseconds((long)raw).UtcDateTime
        : DateTimeOffset.FromUnixTimeSeconds((long)raw).UtcDateTime;

    /// <summary>ISO 8601 字符串解析（兼容小数秒）</summary>
    public static DateTime? ParseIso(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dto)
            ? dto.UtcDateTime
            : null;
    }
}
