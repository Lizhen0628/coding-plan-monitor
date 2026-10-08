using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Media;

namespace CodingPlanMonitor;

// MARK: - 供应商

[JsonConverter(typeof(ProviderJsonConverter))]
public enum Provider { Glm, Kimi, Volcengine, Alibaba, Claude, OpenAi, MiniMax, Copilot, Gemini, DeepSeek }

/// <summary>凭证形态</summary>
public enum CredentialKind
{
    ApiKey,      // 单个 API Key
    AkSk,        // AccessKey ID + Secret Access Key（火山）
    ClaudeOAuth, // Claude Code OAuth Token
    CodexOAuth,  // Codex Access Token + Account ID
    GeminiOAuth, // Gemini CLI OAuth Refresh Token
}

public static class ProviderInfo
{
    public static IReadOnlyList<Provider> All { get; } = (Provider[])Enum.GetValues(typeof(Provider));

    /// <summary>与 macOS 版一致的 JSON 存储值</summary>
    public static string RawValue(Provider p) => p switch
    {
        Provider.Glm => "glm",
        Provider.Kimi => "kimi",
        Provider.Volcengine => "volcengine",
        Provider.Alibaba => "alibaba",
        Provider.Claude => "claude",
        Provider.OpenAi => "openai",
        Provider.MiniMax => "minimax",
        Provider.Copilot => "copilot",
        Provider.Gemini => "gemini",
        Provider.DeepSeek => "deepseek",
        _ => "glm",
    };

    public static Provider FromRaw(string? raw) => raw switch
    {
        "kimi" => Provider.Kimi,
        "volcengine" => Provider.Volcengine,
        "alibaba" => Provider.Alibaba,
        "claude" => Provider.Claude,
        "openai" => Provider.OpenAi,
        "minimax" => Provider.MiniMax,
        "copilot" => Provider.Copilot,
        "gemini" => Provider.Gemini,
        "deepseek" => Provider.DeepSeek,
        _ => Provider.Glm,
    };

    public static string DisplayName(Provider p) => p switch
    {
        Provider.Glm => "GLM Coding",
        Provider.Kimi => "Kimi Coding",
        Provider.Volcengine => "火山引擎 Coding",
        Provider.Alibaba => "通义 Coding",
        Provider.Claude => "Claude Code",
        Provider.OpenAi => "OpenAI Codex",
        Provider.MiniMax => "MiniMax Coding",
        Provider.Copilot => "GitHub Copilot",
        Provider.Gemini => "Gemini CLI",
        Provider.DeepSeek => "DeepSeek",
        _ => p.ToString(),
    };

    /// <summary>紧凑前缀（托盘 tooltip / 徽标）</summary>
    public static string ShortLabel(Provider p) => p switch
    {
        Provider.Glm => "G",
        Provider.Kimi => "K",
        Provider.Volcengine => "V",
        Provider.Alibaba => "T",
        Provider.Claude => "C",
        Provider.OpenAi => "O",
        Provider.MiniMax => "M",
        Provider.Copilot => "P",
        Provider.Gemini => "Ge",
        Provider.DeepSeek => "D",
        _ => "?",
    };

    /// <summary>徽标颜色（与 macOS 版 SwiftUI 系统色一致）</summary>
    public static Color TintColor(Provider p) => p switch
    {
        Provider.Glm => Color.FromRgb(0x58, 0x56, 0xD6),       // indigo
        Provider.Kimi => Color.FromRgb(0x00, 0x7A, 0xFF),      // blue
        Provider.Volcengine => Color.FromRgb(0xFF, 0x3B, 0x30),// red
        Provider.Alibaba => Color.FromRgb(0xAF, 0x52, 0xDE),   // purple
        Provider.Claude => Color.FromRgb(0xFF, 0x95, 0x00),    // orange
        Provider.OpenAi => Color.FromRgb(0x28, 0xCD, 0x41),    // green
        Provider.MiniMax => Color.FromRgb(0x32, 0xAD, 0xE6),   // cyan
        Provider.Copilot => Color.FromRgb(0x8E, 0x8E, 0x93),   // gray
        Provider.Gemini => Color.FromRgb(0x30, 0xB0, 0xC7),    // teal
        Provider.DeepSeek => Color.FromRgb(0xFF, 0x37, 0x5F),  // pink
        _ => Colors.Gray,
    };

    public static CredentialKind Kind(Provider p) => p switch
    {
        Provider.Volcengine => CredentialKind.AkSk,
        Provider.Claude => CredentialKind.ClaudeOAuth,
        Provider.OpenAi => CredentialKind.CodexOAuth,
        Provider.Gemini => CredentialKind.GeminiOAuth,
        _ => CredentialKind.ApiKey,
    };

    /// <summary>备注名示例</summary>
    public static string NameExample(Provider p) => p switch
    {
        Provider.Glm => "智谱 1",
        Provider.Kimi => "Kimi 1",
        Provider.Volcengine => "火山 1",
        Provider.Alibaba => "通义 1",
        Provider.Claude => "Claude 1",
        Provider.OpenAi => "Codex 1",
        Provider.MiniMax => "MiniMax 1",
        Provider.Copilot => "Copilot 1",
        Provider.Gemini => "Gemini 1",
        Provider.DeepSeek => "DeepSeek 1",
        _ => "账号 1",
    };

    /// <summary>凭证展示标签；Secondary 仅火山/Codex 等双凭证供应商有值</summary>
    public static (string Primary, string? Secondary) CredentialLabels(Provider p) => p switch
    {
        Provider.Volcengine => ("AccessKey", "Secret Access Key"),
        Provider.OpenAi => ("Access Token", "Account ID"),
        Provider.Claude or Provider.Copilot => ("OAuth Token", null),
        Provider.Gemini => ("Refresh Token", null),
        _ => ("API Key", null),
    };

    /// <summary>区域选项（多区域供应商）</summary>
    public static (string Value, string Label)[]? RegionOptions(Provider p) => p switch
    {
        Provider.Alibaba => new[]
        {
            ("cn", "国内（bailian.console.aliyun.com）"),
            ("intl", "国际（modelstudio.console.alibabacloud.com）"),
        },
        Provider.MiniMax => new[]
        {
            ("cn", "国内（api.minimaxi.com）"),
            ("intl", "国际（api.minimax.io）"),
        },
        _ => null,
    };

    public static string? RegionCaption(Provider p) => p switch
    {
        Provider.Alibaba => "国内部分账号暂不支持 API Key 查询，如遇报错请切换到国际区域",
        Provider.MiniMax => "API Key 需与平台区域一致",
        _ => null,
    };

    /// <summary>凭证输入框占位/提示</summary>
    public static string KeyPlaceholder(Provider p) => p switch
    {
        Provider.Kimi => "sk-kimi-…",
        Provider.Alibaba => "sk-sp-…",
        Provider.Claude => "sk-ant-oat…",
        Provider.Volcengine => "AccessKey ID",
        Provider.OpenAi => "Access Token",
        Provider.Copilot => "gho_…（GitHub OAuth Token）",
        Provider.Gemini => "1//…（Refresh Token）",
        Provider.DeepSeek => "sk-…",
        _ => "从控制台获取",
    };

    public static string KeyHelpUrl(Provider p) => p switch
    {
        Provider.Glm => "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys",
        Provider.Kimi => "https://www.kimi.com/code/console",
        Provider.Volcengine => "https://console.volcengine.com/iam/keymanage/",
        Provider.Alibaba => "https://bailian.console.aliyun.com/cn-beijing/?tab=plan#/efm/subscription/coding-plan",
        Provider.Claude => "https://claude.ai/settings",
        Provider.OpenAi => "https://chatgpt.com",
        Provider.MiniMax => "https://platform.minimaxi.com/user-center/payment/coding-plan",
        Provider.Copilot => "https://github.com/settings/billing",
        Provider.Gemini => "https://github.com/google-gemini/gemini-cli",
        Provider.DeepSeek => "https://platform.deepseek.com/api_keys",
        _ => "about:blank",
    };
}

/// <summary>供应商 JSON 序列化（与 macOS 版相同的字符串值）</summary>
public sealed class ProviderJsonConverter : JsonConverter<Provider>
{
    public override Provider Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => ProviderInfo.FromRaw(reader.GetString());

    public override void Write(Utf8JsonWriter writer, Provider value, JsonSerializerOptions options)
        => writer.WriteStringValue(ProviderInfo.RawValue(value));
}

// MARK: - 账号（同一供应商可配置多个订阅）

public sealed class Account
{
    [JsonPropertyName("id")] public Guid Id { get; set; } = Guid.NewGuid();
    [JsonPropertyName("provider")] public Provider Provider { get; set; } = Provider.Glm;
    /// <summary>用户备注名，如「智谱 1」，留空则自动命名</summary>
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("apiKey")] public string ApiKey { get; set; } = "";
    /// <summary>GLM 专用："bigmodel"（国内）或 "zai"（国际）</summary>
    [JsonPropertyName("glmPlatform")] public string GlmPlatform { get; set; } = "bigmodel";
    /// <summary>第二凭证字段：火山的 Secret Access Key / OpenAI Codex 的 Account ID</summary>
    [JsonPropertyName("secretKey")] public string SecretKey { get; set; } = "";
    /// <summary>通义/MiniMax 专用："cn"（国内）或 "intl"（国际）</summary>
    [JsonPropertyName("region")] public string Region { get; set; } = "cn";
    /// <summary>是否在监控面板与托盘中显示该订阅的用量</summary>
    [JsonPropertyName("isVisible")] public bool IsVisible { get; set; } = true;

    /// <summary>凭证是否已填写完整</summary>
    [JsonIgnore]
    public bool IsConfigured
    {
        get
        {
            var key = ApiKey.Trim();
            return Provider == Provider.Volcengine
                ? key.Length > 0 && SecretKey.Trim().Length > 0
                : key.Length > 0;
        }
    }

    public Account Copy() => (Account)MemberwiseClone();
}

// MARK: - 归一化视图模型（各供应商解析后统一成这个结构）

public sealed class QuotaWindow
{
    /// <summary>已用百分比 0~100</summary>
    public double Percentage { get; set; }
    /// <summary>UTC 时间</summary>
    public DateTime? ResetDate { get; set; }
}

public sealed class McpUsage
{
    public int Used { get; set; }
    public int Total { get; set; }
    public int Remaining { get; set; }
}

/// <summary>带自定义标签的额外配额窗口（如 Gemini 的 Pro/Flash 每日配额）</summary>
public sealed class ExtraQuota
{
    public string Label { get; set; } = "";
    public double Percentage { get; set; }
    public DateTime? ResetDate { get; set; }
}

/// <summary>账户余额（DeepSeek 等按量计费平台）</summary>
public sealed class BalanceInfo
{
    public double Total { get; set; }
    public double Granted { get; set; }
    public string Currency { get; set; } = "CNY";

    public string Symbol => Currency.ToUpperInvariant() switch
    {
        "CNY" => "¥",
        "USD" => "$",
        "EUR" => "€",
        var c => c + " ",
    };
}

public sealed class ProviderUsage
{
    public QuotaWindow? FiveHour { get; set; }
    public QuotaWindow? Weekly { get; set; }
    /// <summary>每月总额度（Kimi 提供，无重置时间）</summary>
    public QuotaWindow? Monthly { get; set; }
    public McpUsage? Mcp { get; set; }
    /// <summary>套餐等级，如 "lite" / "pro"</summary>
    public string? Level { get; set; }
    public List<ExtraQuota> Extras { get; set; } = new();
    public BalanceInfo? Balance { get; set; }
}
