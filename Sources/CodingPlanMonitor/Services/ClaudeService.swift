import Foundation

// MARK: - Claude（Anthropic Pro/Max 订阅）
// GET https://api.anthropic.com/api/oauth/usage（未公开接口，Claude Code 内部使用）
// 凭证为 Claude Code 的 OAuth Token（sk-ant-oat-…）。

enum ClaudeService {
    static func fetch(oauthToken: String) async throws -> ProviderUsage {
        let token = oauthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw QuotaServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.59", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw QuotaServiceError.apiError("OAuth Token 无效或已过期，请重新从本机导入")
            }
            throw QuotaServiceError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        guard decoded.fiveHour != nil || decoded.sevenDay != nil else {
            throw QuotaServiceError.invalidResponse
        }
        return ProviderUsage(
            fiveHour: decoded.fiveHour?.window,
            weekly: decoded.sevenDay?.window,
            monthly: nil,
            mcp: nil,
            level: nil
        )
    }
}

private struct ClaudeUsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: FlexibleResetTime?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var window: QuotaWindow {
            QuotaWindow(percentage: utilization ?? 0, resetDate: resetsAt?.date)
        }
    }
    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
