import Foundation

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
        // 5 小时窗口按 window 元数据识别（300 分钟），兜底取第一个窗口
        let fiveHourItem = decoded.limits?.first {
            $0.window?.duration == 300 && $0.window?.timeUnit == "TIME_UNIT_MINUTE"
        } ?? decoded.limits?.first
        let fiveHour = fiveHourItem?.detail?.window
        let weekly = decoded.usage?.window
        guard fiveHour != nil || weekly != nil else {
            throw QuotaServiceError.invalidResponse
        }
        // totalQuota 可能为空对象（未开通每月额度时不返回数据），limit 缺失则视为无
        let monthly = decoded.totalQuota.flatMap { quota in
            (quota.limit?.value ?? 0) > 0 ? quota.window : nil
        }
        return ProviderUsage(
            fiveHour: fiveHour,
            weekly: weekly,
            monthly: monthly,
            mcp: nil,
            level: Self.normalizeLevel(decoded.user?.membership?.level)
        )
    }

    /// "LEVEL_INTERMEDIATE" → "intermediate"
    private static func normalizeLevel(_ level: String?) -> String? {
        guard let level, !level.isEmpty else { return nil }
        var text = level
        if let range = text.range(of: #"^LEVEL[_ ]"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.lowercased()
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
