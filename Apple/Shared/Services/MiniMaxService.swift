import Foundation

// MARK: - MiniMax Coding Plan
// GET {host}/v1/api/openplatform/coding_plan/remains
// 国内 host: api.minimaxi.com，国际 host: api.minimax.io
// 凭证：开放平台 API Key（Bearer）。
// 注意：响应中的 usage_count 字段实为「剩余」额度。

enum MiniMaxService {
    static func fetch(apiKey: String, region: String) async throws -> ProviderUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QuotaServiceError.missingAPIKey }
        let host = region == "intl" ? "https://api.minimax.io" : "https://api.minimaxi.com"
        guard let url = URL(string: host + "/v1/api/openplatform/coding_plan/remains") else {
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

        let decoded = try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: data)
        let baseResp = decoded.data?.baseResp ?? decoded.baseResp
        if let code = baseResp?.statusCode, code != 0 {
            let message = baseResp?.statusMsg ?? "错误码 \(code)"
            if code == 1004 || message.lowercased().contains("login") {
                throw QuotaServiceError.apiError("API Key 无效或区域不匹配，请检查凭证与区域设置")
            }
            throw QuotaServiceError.apiError(message)
        }

        // 多模型时取第一个有窗口数据的条目
        guard let model = decoded.data?.modelRemains?.first(where: {
            ($0.currentIntervalTotalCount?.value ?? 0) > 0
        }) ?? decoded.data?.modelRemains?.first else {
            throw QuotaServiceError.apiError("未查询到用量数据，请确认已订阅 Coding Plan")
        }

        return ProviderUsage(
            fiveHour: Self.window(
                total: model.currentIntervalTotalCount?.value,
                remaining: model.currentIntervalUsageCount?.value,
                remainingPercent: model.currentIntervalRemainingPercent?.value,
                reset: model.endTime?.value),
            weekly: Self.window(
                total: model.currentWeeklyTotalCount?.value,
                remaining: model.currentWeeklyUsageCount?.value,
                remainingPercent: model.currentWeeklyRemainingPercent?.value,
                reset: model.weeklyEndTime?.value),
            monthly: nil,
            mcp: nil,
            level: model.modelName
        )
    }

    /// usage_count 为剩余额度；优先用 total/remaining 计算，兜底用 remaining_percent
    private static func window(total: Double?, remaining: Double?, remainingPercent: Double?, reset: Double?) -> QuotaWindow? {
        var used: Double?
        if let total, total > 0, let remaining {
            used = (total - remaining) / total * 100
        } else if let remainingPercent {
            used = 100 - remainingPercent
        }
        guard let used else { return nil }
        return QuotaWindow(percentage: used, resetDate: Self.date(from: reset))
    }

    /// 时间戳兼容秒/毫秒
    private static func date(from value: Double?) -> Date? {
        guard let raw = value else { return nil }
        if raw > 1_000_000_000_000 { return Date(timeIntervalSince1970: raw / 1000) }
        if raw > 1_000_000_000 { return Date(timeIntervalSince1970: raw) }
        return nil
    }
}

// MARK: - 响应模型

private struct MiniMaxRemainsResponse: Decodable {
    struct BaseResp: Decodable {
        let statusCode: Int?
        let statusMsg: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMsg = "status_msg"
        }
    }

    struct ModelRemains: Decodable {
        let modelName: String?
        let currentIntervalTotalCount: FlexibleDouble?
        /// 注意：字段名叫 usage_count，但实际值是「剩余」额度
        let currentIntervalUsageCount: FlexibleDouble?
        let currentIntervalRemainingPercent: FlexibleDouble?
        let endTime: FlexibleDouble?
        let currentWeeklyTotalCount: FlexibleDouble?
        let currentWeeklyUsageCount: FlexibleDouble?
        let currentWeeklyRemainingPercent: FlexibleDouble?
        let weeklyEndTime: FlexibleDouble?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case currentIntervalTotalCount = "current_interval_total_count"
            case currentIntervalUsageCount = "current_interval_usage_count"
            case currentIntervalRemainingPercent = "current_interval_remaining_percent"
            case endTime = "end_time"
            case currentWeeklyTotalCount = "current_weekly_total_count"
            case currentWeeklyUsageCount = "current_weekly_usage_count"
            case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
            case weeklyEndTime = "weekly_end_time"
        }
    }

    struct Payload: Decodable {
        let modelRemains: [ModelRemains]?
        let baseResp: BaseResp?

        enum CodingKeys: String, CodingKey {
            case modelRemains = "model_remains"
            case baseResp = "base_resp"
        }
    }

    let data: Payload?
    let baseResp: BaseResp?

    enum CodingKeys: String, CodingKey {
        case data
        case baseResp = "base_resp"
    }
}
