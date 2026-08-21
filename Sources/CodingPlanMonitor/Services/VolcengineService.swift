import Foundation
import CryptoKit

// MARK: - 火山引擎（Volcengine Coding Plan）
// POST https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01
// 使用火山 V4 HMAC-SHA256 签名（service: ark），凭证为 AK/SK 对。

enum VolcengineService {
    static func fetch(accessKey: String, secretKey: String) async throws -> ProviderUsage {
        let ak = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sk = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ak.isEmpty, !sk.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01") else {
            throw QuotaServiceError.invalidResponse
        }

        let body = Data()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        VolcengineSigner.sign(request: &request, body: body, accessKey: ak, secretKey: sk)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw QuotaServiceError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(VolcUsageResponse.self, from: data)
        if let message = decoded.responseMetadata?.error?.message, !message.isEmpty {
            throw QuotaServiceError.apiError(message)
        }
        guard let result = decoded.result else {
            throw QuotaServiceError.invalidResponse
        }

        var fiveHour: QuotaWindow?
        var weekly: QuotaWindow?
        var monthly: QuotaWindow?
        for quota in result.quotaUsage ?? [] {
            let percent = Self.normalizePercent(quota.percent)
            let reset = quota.resetTimestamp.map { Date(timeIntervalSince1970: $0) }
            let window = QuotaWindow(percentage: percent, resetDate: reset)
            switch quota.level?.lowercased() ?? "" {
            case let level where level.contains("session") || level.contains("5h") || level.contains("5-hour") || level.contains("five"):
                fiveHour = window
            case let level where level.contains("week"):
                weekly = window
            case let level where level.contains("month"):
                monthly = window
            default:
                if fiveHour == nil { fiveHour = window }
            }
        }
        guard fiveHour != nil || weekly != nil || monthly != nil else {
            throw QuotaServiceError.apiError("未查询到用量数据，请确认账号已开通 Coding Plan")
        }
        return ProviderUsage(fiveHour: fiveHour, weekly: weekly, monthly: monthly, mcp: nil, level: nil)
    }

    /// Percent 可能是 0~1 小数或 0~100 数值
    private static func normalizePercent(_ value: Double?) -> Double {
        guard let value else { return 0 }
        return value <= 1 ? value * 100 : value
    }
}

private struct VolcUsageResponse: Decodable {
    struct ResultPayload: Decodable {
        struct Quota: Decodable {
            let level: String?
            let percent: Double?
            /// 秒级时间戳
            let resetTimestamp: TimeInterval?

            enum CodingKeys: String, CodingKey {
                case level = "Level"
                case percent = "Percent"
                case resetTimestamp = "ResetTimestamp"
            }
        }
        let quotaUsage: [Quota]?

        enum CodingKeys: String, CodingKey {
            case quotaUsage = "QuotaUsage"
        }
    }
    struct Metadata: Decodable {
        struct ErrorPayload: Decodable {
            let message: String?

            enum CodingKeys: String, CodingKey {
                case message = "Message"
            }
        }
        let error: ErrorPayload?

        enum CodingKeys: String, CodingKey {
            case error = "Error"
        }
    }
    let result: ResultPayload?
    let responseMetadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case result = "Result"
        case responseMetadata = "ResponseMetadata"
    }
}

