import Foundation

// MARK: - DeepSeek（按量计费账户余额）
// GET https://api.deepseek.com/user/balance
// 凭证：开放平台 API Key（sk-…）。
// 返回人民币/美元余额（含赠送额度），数值字段以字符串形式返回。

enum DeepSeekService {
    static func fetch(apiKey: String) async throws -> ProviderUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QuotaServiceError.missingAPIKey }
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
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

        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        guard let info = decoded.balanceInfos?.first,
              let total = Double(info.totalBalance ?? "") else {
            throw QuotaServiceError.invalidResponse
        }
        let balance = BalanceInfo(
            total: total,
            granted: Double(info.grantedBalance ?? "") ?? 0,
            currency: info.currency ?? "CNY"
        )
        return ProviderUsage(
            fiveHour: nil,
            weekly: nil,
            monthly: nil,
            mcp: nil,
            level: decoded.isAvailable == false ? "余额不足" : nil,
            balance: balance
        )
    }
}

// MARK: - 响应模型

private struct DeepSeekBalanceResponse: Decodable {
    struct Info: Decodable {
        let currency: String?
        let totalBalance: String?
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    let isAvailable: Bool?
    let balanceInfos: [Info]?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}
