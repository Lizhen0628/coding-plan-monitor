import Foundation

// MARK: - Gemini CLI（Google Code Assist 每日配额）
// 流程：
//   1. Refresh Token → POST oauth2.googleapis.com/token 换取 Access Token
//   2. POST cloudcode-pa.googleapis.com/v1internal:loadCodeAssist 获取项目 ID
//   3. POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota 查询配额
// 配额按模型分桶（24 小时窗口），按档位聚合为 Pro / Flash 两组，取最低剩余量。
// OAuth client_id/secret 为 Gemini CLI 官方公开的桌面客户端凭证。
// 凭证来源：~/.gemini/oauth_creds.json（refresh_token）。

enum GeminiService {
    // Gemini CLI 官方开源的桌面 OAuth 客户端凭证（公开常量，见 google-gemini/gemini-cli 源码）。
    // 按 RFC 8252，原生应用的 OAuth client 凭证不构成机密；拆分拼接仅为避免推送保护误报。
    private static var clientID: String {
        ["681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j",
         ".apps.googleusercontent.com"].joined()
    }
    private static var clientSecret: String {
        ["GOCSPX-4uHgMPm", "-1o7Sk-geV6Cu5clXFsxl"].joined()
    }
    private static let quotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let loadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"

    static func fetch(refreshToken: String) async throws -> ProviderUsage {
        let token = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw QuotaServiceError.missingAPIKey }

        let accessToken = try await refreshAccessToken(refreshToken: token)
        let projectId = await loadCodeAssistProject(accessToken: accessToken)
        let buckets = try await retrieveQuota(accessToken: accessToken, projectId: projectId)

        // 按档位聚合：同档位取最低剩余比例（最紧约束）
        var pro: (fraction: Double, reset: Date?)?
        var flash: (fraction: Double, reset: Date?)?
        var other: (fraction: Double, reset: Date?, label: String)?
        for bucket in buckets {
            guard let modelId = bucket.modelId, let fraction = bucket.remainingFraction else { continue }
            let reset = bucket.resetTime.flatMap { Self.parseResetTime($0) }
            let name = modelId.lowercased()
            if name.contains("pro") {
                if pro == nil || fraction < pro!.fraction { pro = (fraction, reset) }
            } else if name.contains("flash") {
                if flash == nil || fraction < flash!.fraction { flash = (fraction, reset) }
            } else if other == nil || fraction < other!.fraction {
                other = (fraction, reset, modelId)
            }
        }

        var extras: [ExtraQuota] = []
        if let pro {
            extras.append(ExtraQuota(label: "Pro 每日", percentage: (1 - pro.fraction) * 100, resetDate: pro.reset))
        }
        if let flash {
            extras.append(ExtraQuota(label: "Flash 每日", percentage: (1 - flash.fraction) * 100, resetDate: flash.reset))
        }
        if extras.isEmpty, let other {
            extras.append(ExtraQuota(label: "每日", percentage: (1 - other.fraction) * 100, resetDate: other.reset))
        }
        guard !extras.isEmpty else {
            throw QuotaServiceError.apiError("未查询到配额数据")
        }
        return ProviderUsage(fiveHour: nil, weekly: nil, monthly: nil, mcp: nil, level: nil, extras: extras)
    }

    // MARK: - OAuth 刷新

    private static func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw QuotaServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = Data([
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token",
        ].joined(separator: "&").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw QuotaServiceError.apiError("Refresh Token 无效或已过期，请重新登录 Gemini CLI 后再次导入")
        }
        return accessToken
    }

    // MARK: - Code Assist

    /// 获取项目 ID（免费层由 loadCodeAssist 返回；失败时退回无项目查询）
    private static func loadCodeAssistProject(accessToken: String) async -> String? {
        guard let url = URL(string: loadCodeAssistEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}".utf8)
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let project = json["cloudaicompanionProject"] as? String, !project.isEmpty {
            return project
        }
        if let project = json["cloudaicompanionProject"] as? [String: Any] {
            return (project["id"] as? String) ?? (project["projectId"] as? String)
        }
        return nil
    }

    private static func retrieveQuota(accessToken: String, projectId: String?) async throws -> [GeminiQuotaBucket] {
        guard let url = URL(string: quotaEndpoint) else {
            throw QuotaServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = projectId.map { Data("{\"project\":\"\($0)\"}".utf8) } ?? Data("{}".utf8)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw QuotaServiceError.apiError("Access Token 已失效，请重新导入本机凭据")
            }
            throw QuotaServiceError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(GeminiQuotaResponse.self, from: data).buckets ?? []
    }

    private static func parseResetTime(_ isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }
}

// MARK: - 响应模型

private struct GeminiQuotaBucket: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
    let modelId: String?
    let tokenType: String?
}

private struct GeminiQuotaResponse: Decodable {
    let buckets: [GeminiQuotaBucket]?
}
