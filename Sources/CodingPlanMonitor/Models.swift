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
    /// 每月总额度（Kimi 提供，无重置时间）
    var monthly: QuotaWindow?
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
// 注意：该接口的数值字段（used/limit/remaining）以字符串形式返回。
// 实测结构：
// {
//   "user": {"membership": {"level": "LEVEL_INTERMEDIATE"}},
//   "usage":  {"used":"…","limit":"…","remaining":"…","resetTime":"ISO8601"},  // 每周额度
//   "limits": [{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},        // 5 小时窗口
//               "detail":{"used":"…","limit":"…","remaining":"…","resetTime":"…"}}],
//   "totalQuota": {"limit":"…","remaining":"…"}                                 // 每月总额度
// }

struct KimiUsagesResponse: Decodable {
    struct Detail: Decodable {
        let used: FlexibleDouble?
        let limit: FlexibleDouble?
        let remaining: FlexibleDouble?
        let resetTime: FlexibleResetTime?
    }

    struct LimitItem: Decodable {
        struct Window: Decodable {
            /// 分钟数，5 小时窗口为 300
            let duration: Int?
            let timeUnit: String?
        }
        let window: Window?
        let detail: Detail?
    }

    struct TotalQuota: Decodable {
        let limit: FlexibleDouble?
        let remaining: FlexibleDouble?
    }

    struct User: Decodable {
        struct Membership: Decodable {
            /// 如 "LEVEL_INTERMEDIATE"
            let level: String?
        }
        let membership: Membership?
    }

    let user: User?
    /// 每周额度
    let usage: Detail?
    /// 限流窗口列表，含 5 小时窗口
    let limits: [LimitItem]?
    /// 每月总额度（无重置时间）
    let totalQuota: TotalQuota?
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

/// 数值兼容字符串与 JSON 数字（Kimi 接口以字符串返回）
struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self) {
            value = Double(string)
        } else {
            value = nil
        }
    }
}

extension KimiUsagesResponse.Detail {
    var window: QuotaWindow {
        let limit = self.limit?.value ?? 0
        let used = self.used?.value ?? max(0, limit - (remaining?.value ?? 0))
        let percentage = limit > 0 ? used / limit * 100 : 0
        return QuotaWindow(percentage: percentage, resetDate: resetTime?.date)
    }
}

extension KimiUsagesResponse.TotalQuota {
    var window: QuotaWindow {
        let limit = self.limit?.value ?? 0
        let used = max(0, limit - (remaining?.value ?? 0))
        let percentage = limit > 0 ? used / limit * 100 : 0
        return QuotaWindow(percentage: percentage, resetDate: nil)
    }
}
