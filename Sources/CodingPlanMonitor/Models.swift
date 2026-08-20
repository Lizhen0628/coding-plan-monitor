import Foundation

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
    var mcp: MCPUsage?
    /// 套餐等级，如 "lite" / "pro"
    var level: String?
}

// MARK: - GLM（智谱）响应模型
// GET {base}/api/monitor/usage/quota/limit

struct QuotaResponse: Decodable {
    let code: Int?
    let msg: String?
    let success: Bool?
    let data: QuotaData?
}

struct QuotaData: Decodable {
    let limits: [UsageLimit]
    let level: String?
}

/// GLM 单个限额项。
/// - TOKENS_LIMIT / CREDIT_LIMIT: token 额度，unit 3 = 5 小时窗口，unit 6 = 每周窗口
/// - TIME_LIMIT: MCP 每月调用次数（usage 总量 / currentValue 已用 / remaining 剩余）
struct UsageLimit: Decodable {
    let type: String
    let unit: Int?
    let number: Int?
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
    let percentage: Double?
    /// 毫秒时间戳
    let nextResetTime: Int64?

    var resetDate: Date? {
        nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    var window: QuotaWindow {
        QuotaWindow(percentage: percentage ?? 0, resetDate: resetDate)
    }
}

// MARK: - Kimi 响应模型
// GET https://api.kimi.com/coding/v1/usages

struct KimiUsagesResponse: Decodable {
    struct Detail: Decodable {
        let limit: Double?
        let remaining: Double?
        let resetTime: FlexibleResetTime?
    }

    struct LimitItem: Decodable {
        let detail: Detail?
    }

    let limits: [LimitItem]?
    /// 每周总额度
    let usage: Detail?
}

/// resetTime 兼容 ISO 8601 字符串与秒/毫秒时间戳
struct FlexibleResetTime: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: string) {
                date = parsed
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: string)
            }
        } else if let number = try? container.decode(Int64.self) {
            guard number > 0 else {
                date = nil
                return
            }
            // 秒级时间戳 < 1e12，毫秒 >= 1e12
            date = Date(timeIntervalSince1970: number < 1_000_000_000_000
                ? TimeInterval(number)
                : TimeInterval(number) / 1000)
        } else {
            date = nil
        }
    }
}

extension KimiUsagesResponse.Detail {
    var window: QuotaWindow {
        let limit = self.limit ?? 0
        let remaining = self.remaining ?? 0
        let used = max(0, limit - remaining)
        let percentage = limit > 0 ? used / limit * 100 : 0
        return QuotaWindow(percentage: percentage, resetDate: resetTime?.date)
    }
}
