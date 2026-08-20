import Foundation

enum QuotaServiceError: LocalizedError {
    case missingAPIKey
    case httpError(Int)
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置中填入 API Key"
        case .httpError(let code):
            if code == 401 || code == 403 {
                return "API Key 无效或已过期（HTTP \(code)）"
            }
            return "请求失败（HTTP \(code)）"
        case .apiError(let msg): return msg
        case .invalidResponse: return "响应数据格式异常"
        }
    }
}

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
            mcp: mcp.flatMap { item in
                guard let used = item.currentValue, let total = item.usage else { return nil }
                return MCPUsage(used: used, total: total, remaining: item.remaining ?? max(0, total - used))
            },
            level: quota.level
        )
    }
}

// MARK: - Kimi（月之暗面）

enum KimiService {
    static func fetch(apiKey: String) async throws -> ProviderUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: "https://api.kimi.com/coding/v1/usages") else {
            throw QuotaServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw QuotaServiceError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(KimiUsagesResponse.self, from: data)
        let fiveHour = decoded.limits?.compactMap(\.detail).first?.window
        let weekly = decoded.usage?.window
        guard fiveHour != nil || weekly != nil else {
            throw QuotaServiceError.invalidResponse
        }
        return ProviderUsage(fiveHour: fiveHour, weekly: weekly, mcp: nil, level: nil)
    }
}
