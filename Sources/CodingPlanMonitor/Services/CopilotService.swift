import Foundation

// MARK: - GitHub Copilot（Premium 请求额度）
// GET https://api.github.com/copilot_internal/user
// 凭证：GitHub OAuth Token（gho_…，Copilot CLI/IDE 插件登录后生成，
// 存放于 ~/.config/github-copilot/hosts.json）。
// 返回 quota_snapshots.premium_interactions（每月高级请求额度）等。

enum CopilotService {
    static func fetch(oauthToken: String) async throws -> ProviderUsage {
        let token = oauthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            throw QuotaServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw QuotaServiceError.apiError("Token 无效或已过期，请重新导入或粘贴")
            }
            throw QuotaServiceError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)
        guard let snapshot = decoded.quotaSnapshots?.premiumInteractions ?? decoded.quotaSnapshots?.chat else {
            throw QuotaServiceError.apiError("未查询到配额数据，请确认账号有 Copilot 订阅")
        }
        guard snapshot.unlimited != true else {
            throw QuotaServiceError.apiError("当前订阅为无限额度，无需监控")
        }

        var used: Double = 0
        if let entitlement = snapshot.entitlement, entitlement > 0, let remaining = snapshot.remaining {
            used = (entitlement - remaining) / entitlement * 100
        } else if let percentRemaining = snapshot.percentRemaining {
            used = 100 - percentRemaining
        }

        return ProviderUsage(
            fiveHour: nil,
            weekly: nil,
            monthly: QuotaWindow(percentage: used, resetDate: Self.parseResetDate(decoded.quotaResetDate)),
            mcp: nil,
            level: decoded.copilotPlan
        )
    }

    /// quota_reset_date 兼容 "2025-07-01" 与 ISO8601 日期时间
    private static func parseResetDate(_ value: String?) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: raw)
    }
}

// MARK: - 响应模型

private struct CopilotUsageResponse: Decodable {
    struct QuotaSnapshots: Decodable {
        struct Snapshot: Decodable {
            let entitlement: Double?
            let remaining: Double?
            let percentRemaining: Double?
            let unlimited: Bool?

            enum CodingKeys: String, CodingKey {
                case entitlement
                case remaining
                case percentRemaining = "percent_remaining"
                case unlimited
            }
        }

        let premiumInteractions: Snapshot?
        let chat: Snapshot?

        enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
            case chat
        }
    }

    let quotaSnapshots: QuotaSnapshots?
    let copilotPlan: String?
    let quotaResetDate: String?

    enum CodingKeys: String, CodingKey {
        case quotaSnapshots = "quota_snapshots"
        case copilotPlan = "copilot_plan"
        case quotaResetDate = "quota_reset_date"
    }
}
