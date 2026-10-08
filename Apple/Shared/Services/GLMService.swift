import Foundation

// MARK: - GLM（智谱）

enum GLMService {
    static func fetch(apiKey: String, baseURL: String) async throws -> ProviderUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: baseURL + "/api/monitor/usage/quota/limit") else {
            throw QuotaServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("zh-CN,zh", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw QuotaServiceError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(QuotaResponse.self, from: data)
        guard decoded.success == true, let quota = decoded.data else {
            throw QuotaServiceError.apiError(decoded.msg ?? "查询失败")
        }
        return Self.parse(quota)
    }

    /// 按 unit 字段分类窗口（unit 3 = 5 小时，unit 6 = 每周），
    /// 缺失或不识别时按重置时间排序兜底。不能用时间排序代替 unit——
    /// 周期末尾每周窗口可能比 5 小时窗口更早重置。
    static func parse(_ quota: QuotaData) -> ProviderUsage {
        var fiveHour: UsageLimit?
        var weekly: UsageLimit?
        var unclassified: [UsageLimit] = []

        for item in quota.limits {
            let type = item.type.lowercased()
            guard type == "tokens_limit" || type == "credit_limit" else { continue }
            switch item.unit {
            case 3 where fiveHour == nil: fiveHour = item
            case 6 where weekly == nil: weekly = item
            default: unclassified.append(item)
            }
        }

        unclassified.sort {
            ($0.nextResetTime ?? .min) < ($1.nextResetTime ?? .min)
        }
        for item in unclassified {
            if fiveHour == nil {
                fiveHour = item
            } else if weekly == nil {
                weekly = item
            }
        }

        let mcp = quota.limits.first { $0.type.uppercased() == "TIME_LIMIT" }
        return ProviderUsage(
            fiveHour: fiveHour?.window,
            weekly: weekly?.window,
            monthly: nil,
            mcp: mcp.flatMap { item in
                guard let used = item.currentValue, let total = item.usage else { return nil }
                return MCPUsage(used: used, total: total, remaining: item.remaining ?? max(0, total - used))
            },
            level: quota.level
        )
    }
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
