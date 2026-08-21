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
