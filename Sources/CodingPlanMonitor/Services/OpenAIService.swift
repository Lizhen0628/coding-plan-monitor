import Foundation

// MARK: - OpenAI（Codex / ChatGPT 订阅）
// GET https://chatgpt.com/backend-api/wham/usage（Codex CLI 内部接口）
// 凭证为 ~/.codex/auth.json 中的 access_token 与 account_id。

enum OpenAIService {
    static func fetch(accessToken: String, accountId: String) async throws -> ProviderUsage {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw QuotaServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codex_cli_rs/0.76.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let account = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !account.isEmpty {
            request.setValue(account, forHTTPHeaderField: "Chatgpt-Account-Id")
        }
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw QuotaServiceError.apiError("Access Token 无效或已过期，请运行 codex 登录后重新导入")
            }
            throw QuotaServiceError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        let fiveHour = decoded.rateLimit?.primaryWindow?.window
        let weekly = decoded.rateLimit?.secondaryWindow?.window
        guard fiveHour != nil || weekly != nil else {
            throw QuotaServiceError.invalidResponse
        }
        return ProviderUsage(fiveHour: fiveHour, weekly: weekly, monthly: nil, mcp: nil, level: nil)
    }
}

private struct CodexUsageResponse: Decodable {
    struct Window: Decodable {
        let usedPercent: Double?
        let resetAfterSeconds: Int?
        let resetAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }

        var window: QuotaWindow {
            let reset: Date? = {
                if let resetAt, resetAt > 0 {
                    return Date(timeIntervalSince1970: TimeInterval(resetAt))
                }
                if let resetAfterSeconds {
                    return Date().addingTimeInterval(TimeInterval(resetAfterSeconds))
                }
                return nil
            }()
            return QuotaWindow(percentage: usedPercent ?? 0, resetDate: reset)
        }
    }
    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}
