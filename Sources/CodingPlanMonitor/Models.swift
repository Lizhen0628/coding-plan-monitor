import Foundation
import SwiftUI

// MARK: - 供应商

enum Provider: String, CaseIterable, Codable {
    case glm
    case kimi
    case volcengine
    case alibaba
    case claude
    case openai
    case minimax
    case copilot
    case gemini
    case deepseek

    var displayName: String {
        switch self {
        case .glm: return "GLM Coding"
        case .kimi: return "Kimi Coding"
        case .volcengine: return "火山引擎 Coding"
        case .alibaba: return "通义 Coding"
        case .claude: return "Claude Code"
        case .openai: return "OpenAI Codex"
        case .minimax: return "MiniMax Coding"
        case .copilot: return "GitHub Copilot"
        case .gemini: return "Gemini CLI"
        case .deepseek: return "DeepSeek"
        }
    }

    /// 菜单栏紧凑前缀
    var shortLabel: String {
        switch self {
        case .glm: return "G"
        case .kimi: return "K"
        case .volcengine: return "V"
        case .alibaba: return "T"
        case .claude: return "C"
        case .openai: return "O"
        case .minimax: return "M"
        case .copilot: return "P"
        case .gemini: return "Ge"
        case .deepseek: return "D"
        }
    }

    /// 徽标颜色
    var tint: Color {
        switch self {
        case .glm: return .indigo
        case .kimi: return .blue
        case .volcengine: return .red
        case .alibaba: return .purple
        case .claude: return .orange
        case .openai: return .green
        case .minimax: return .cyan
        case .copilot: return .gray
        case .gemini: return .teal
        case .deepseek: return .pink
        }
    }

    /// 凭证形态
    enum CredentialKind {
        case apiKey            // 单个 API Key
        case akSK              // AccessKey ID + Secret Access Key（火山）
        case claudeOAuth       // Claude Code OAuth Token
        case codexOAuth        // Codex Access Token + Account ID
        case geminiOAuth       // Gemini CLI OAuth Refresh Token
    }

    var credentialKind: CredentialKind {
        switch self {
        case .volcengine: return .akSK
        case .claude: return .claudeOAuth
        case .openai: return .codexOAuth
        case .gemini: return .geminiOAuth
        default: return .apiKey
        }
    }

    /// 备注名示例
    var nameExample: String {
        switch self {
        case .glm: return "智谱 1"
        case .kimi: return "Kimi 1"
        case .volcengine: return "火山 1"
        case .alibaba: return "通义 1"
        case .claude: return "Claude 1"
        case .openai: return "Codex 1"
        case .minimax: return "MiniMax 1"
        case .copilot: return "Copilot 1"
        case .gemini: return "Gemini 1"
        case .deepseek: return "DeepSeek 1"
        }
    }

    /// 区域选项（多区域供应商）
    var regionOptions: [(value: String, label: String)]? {
        switch self {
        case .alibaba:
            return [("cn", "国内（bailian.console.aliyun.com）"), ("intl", "国际（modelstudio.console.alibabacloud.com）")]
        case .minimax:
            return [("cn", "国内（api.minimaxi.com）"), ("intl", "国际（api.minimax.io）")]
        default:
            return nil
        }
    }

    /// 区域选择器下方的说明
    var regionCaption: String? {
        switch self {
        case .alibaba: return "国内部分账号暂不支持 API Key 查询，如遇报错请切换到国际区域"
        case .minimax: return "API Key 需与平台区域一致"
        default: return nil
        }
    }

    /// 凭证输入框占位/提示
    var keyPlaceholder: String {
        switch self {
        case .kimi: return "sk-kimi-…"
        case .alibaba: return "sk-sp-…"
        case .claude: return "sk-ant-oat…"
        case .volcengine: return "AccessKey ID"
        case .openai: return "Access Token"
        case .copilot: return "gho_…（GitHub OAuth Token）"
        case .gemini: return "1//…（Refresh Token）"
        case .deepseek: return "sk-…"
        default: return "从控制台获取"
        }
    }

    var keyHelpURL: URL {
        switch self {
        case .glm: return URL(string: "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys")!
        case .kimi: return URL(string: "https://www.kimi.com/code/console")!
        case .volcengine: return URL(string: "https://console.volcengine.com/iam/keymanage/")!
        case .alibaba: return URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=plan#/efm/subscription/coding-plan")!
        case .claude: return URL(string: "https://claude.ai/settings")!
        case .openai: return URL(string: "https://chatgpt.com")!
        case .minimax: return URL(string: "https://platform.minimaxi.com/user-center/payment/coding-plan")!
        case .copilot: return URL(string: "https://github.com/settings/billing")!
        case .gemini: return URL(string: "https://github.com/google-gemini/gemini-cli")!
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")!
        }
    }
}

// MARK: - 账号（同一供应商可配置多个订阅）

struct Account: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var provider: Provider
    /// 用户备注名，如「智谱 1」，留空则自动命名
    var name: String = ""
    var apiKey: String = ""
    /// GLM 专用："bigmodel"（国内）或 "zai"（国际）
    var glmPlatform: String = "bigmodel"
    /// 第二凭证字段：火山的 Secret Access Key / OpenAI Codex 的 Account ID
    var secretKey: String = ""
    /// 通义专用："cn"（国内）或 "intl"（国际）
    var region: String = "cn"
    /// 是否在监控面板与菜单栏中显示该订阅的用量
    var isVisible: Bool = true

    /// 凭证是否已填写完整
    var isConfigured: Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .volcengine:
            return !key.isEmpty && !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return !key.isEmpty
        }
    }

    /// 自定义解码：旧版本数据缺少新字段时回退默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? .glm
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        glmPlatform = try container.decodeIfPresent(String.self, forKey: .glmPlatform) ?? "bigmodel"
        secretKey = try container.decodeIfPresent(String.self, forKey: .secretKey) ?? ""
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? "cn"
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
    }

    init(id: UUID = UUID(), provider: Provider, name: String = "", apiKey: String = "", glmPlatform: String = "bigmodel", secretKey: String = "", region: String = "cn", isVisible: Bool = true) {
        self.id = id
        self.provider = provider
        self.name = name
        self.apiKey = apiKey
        self.glmPlatform = glmPlatform
        self.secretKey = secretKey
        self.region = region
        self.isVisible = isVisible
    }
}

// MARK: - 归一化视图模型（各供应商解析后统一成这个结构）

struct QuotaWindow {
    /// 已用百分比 0~100
    var percentage: Double
    var resetDate: Date?
}

struct MCPUsage {
    var used: Int
    var total: Int
    var remaining: Int
}

struct ProviderUsage {
    var fiveHour: QuotaWindow?
    var weekly: QuotaWindow?
    /// 每月总额度（Kimi 提供，无重置时间）
    var monthly: QuotaWindow?
    var mcp: MCPUsage?
    /// 套餐等级，如 "lite" / "pro"
    var level: String?
    /// 额外配额窗口（如 Gemini 的 Pro/Flash 每日配额），带自定义标签
    var extras: [ExtraQuota] = []
    /// 账户余额（DeepSeek 等按量计费平台）
    var balance: BalanceInfo?
}

/// 带自定义标签的额外配额窗口
struct ExtraQuota {
    var label: String
    var percentage: Double
    var resetDate: Date?
}

/// 账户余额
struct BalanceInfo {
    var total: Double
    var granted: Double
    var currency: String

    /// 货币符号
    var symbol: String {
        switch currency.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        default: return currency + " "
        }
    }
}
