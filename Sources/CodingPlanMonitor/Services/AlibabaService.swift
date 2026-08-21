import Foundation

// MARK: - 通义（阿里云百炼 Coding Plan）
// POST {console}/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2
// 凭证为 Coding Plan 专用 API Key（sk-sp-…）。

enum AlibabaService {
    static func fetch(apiKey: String, region: String) async throws -> ProviderUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QuotaServiceError.missingAPIKey }

        let isCN = region != "intl"
        let base = isCN ? "https://bailian.console.aliyun.com" : "https://modelstudio.console.alibabacloud.com"
        var components = URLComponents(string: base + "/data/api.json")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "product", value: "broadscope-bailian"),
            URLQueryItem(name: "api", value: "queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "currentRegionId", value: isCN ? "cn-beijing" : "ap-southeast-1"),
        ]
        guard let url = components?.url else { throw QuotaServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "queryCodingPlanInstanceInfoRequest": [
                "commodityCode": isCN ? "sfm_codingplan_public_cn" : "sfm_codingplan_public_intl",
            ],
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(key, forHTTPHeaderField: "X-DashScope-API-Key")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(base, forHTTPHeaderField: "Origin")
        request.setValue(isCN
            ? "https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan"
            : "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan",
            forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw QuotaServiceError.httpError(http.statusCode)
        }
        return try parse(data)
    }

    /// 响应为控制台网关结构，quota 字段嵌套层级不固定，用深度搜索兜底
    static func parse(_ data: Data) throws -> ProviderUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaServiceError.invalidResponse
        }

        // 错误检测：ConsoleNeedLogin / 非 0/200 状态码
        let codeText = (deepFindString(keys: ["code", "status", "statusCode"], in: object) ?? "").lowercased()
        let messageText = deepFindString(keys: ["message", "msg", "statusMessage"], in: object) ?? ""
        if codeText.contains("needlogin") || messageText.lowercased().contains("console session") {
            throw QuotaServiceError.apiError("该账号当前区域不支持 API Key 查询，请到设置中切换区域")
        }
        if let codeInt = deepFindInt(keys: ["statusCode", "status_code"], in: object),
           codeInt != 0 && codeInt != 200 {
            throw QuotaServiceError.apiError(messageText.isEmpty ? "查询失败（\(codeInt)）" : messageText)
        }

        guard let quota = deepFindDict(containingAny: [
            "per5HourUsedQuota", "per5HourTotalQuota",
            "perWeekUsedQuota", "perWeekTotalQuota",
            "perBillMonthUsedQuota", "perBillMonthTotalQuota",
        ], in: object) else {
            throw QuotaServiceError.apiError("未查询到用量数据，请确认账号已开通 Coding Plan")
        }

        let planName = deepFindString(keys: ["planName", "instanceName", "packageName"], in: object)

        func window(usedKeys: [String], totalKeys: [String], resetKeys: [String]) -> QuotaWindow? {
            guard let total = intValue(forKeys: totalKeys, in: quota), total > 0 else { return nil }
            let used = intValue(forKeys: usedKeys, in: quota) ?? 0
            let reset = dateValue(forKeys: resetKeys, in: quota)
            return QuotaWindow(percentage: min(100, Double(used) / Double(total) * 100), resetDate: reset)
        }

        return ProviderUsage(
            fiveHour: window(
                usedKeys: ["per5HourUsedQuota", "perFiveHourUsedQuota"],
                totalKeys: ["per5HourTotalQuota", "perFiveHourTotalQuota"],
                resetKeys: ["per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime"]),
            weekly: window(
                usedKeys: ["perWeekUsedQuota"],
                totalKeys: ["perWeekTotalQuota"],
                resetKeys: ["perWeekQuotaNextRefreshTime"]),
            monthly: window(
                usedKeys: ["perBillMonthUsedQuota", "perMonthUsedQuota"],
                totalKeys: ["perBillMonthTotalQuota", "perMonthTotalQuota"],
                resetKeys: ["perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime"]),
            mcp: nil,
            level: planName
        )
    }

    // MARK: 深度搜索辅助

    private static func deepFindDict(containingAny keys: [String], in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if keys.contains(where: { dict[$0] != nil }) { return dict }
            for child in dict.values {
                if let found = deepFindDict(containingAny: keys, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = deepFindDict(containingAny: keys, in: child) { return found }
            }
        }
        return nil
    }

    private static func deepFindString(keys: [String], in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let string = dict[key] as? String, !string.isEmpty { return string }
            }
            for child in dict.values {
                if let found = deepFindString(keys: keys, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = deepFindString(keys: keys, in: child) { return found }
            }
        }
        return nil
    }

    private static func deepFindInt(keys: [String], in value: Any) -> Int? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let number = dict[key] as? NSNumber { return number.intValue }
            }
            for child in dict.values {
                if let found = deepFindInt(keys: keys, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = deepFindInt(keys: keys, in: child) { return found }
            }
        }
        return nil
    }

    private static func intValue(forKeys keys: [String], in dict: [String: Any]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber { return number.intValue }
            if let string = dict[key] as? String, let value = Int(string) { return value }
        }
        return nil
    }

    /// 兼容秒/毫秒时间戳与 ISO8601 字符串
    private static func dateValue(forKeys keys: [String], in dict: [String: Any]) -> Date? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                let value = number.doubleValue
                guard value > 0 else { continue }
                return Date(timeIntervalSince1970: value < 1_000_000_000_000 ? value : value / 1000)
            }
            if let string = dict[key] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: string) { return date }
                if let value = Double(string), value > 0 {
                    return Date(timeIntervalSince1970: value < 1_000_000_000_000 ? value : value / 1000)
                }
            }
        }
        return nil
    }
}
