import Foundation

/// resetTime 兼容 ISO 8601 字符串与秒/毫秒时间戳
struct FlexibleResetTime: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: string) {
                date = parsed
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: string)
            }
        } else if let number = try? container.decode(Int64.self) {
            guard number > 0 else {
                date = nil
                return
            }
            // 秒级时间戳 < 1e12，毫秒 >= 1e12
            date = Date(timeIntervalSince1970: number < 1_000_000_000_000
                ? TimeInterval(number)
                : TimeInterval(number) / 1000)
        } else {
            date = nil
        }
    }
}

/// 数值兼容字符串与 JSON 数字（Kimi 接口以字符串返回）
struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self) {
            value = Double(string)
        } else {
            value = nil
        }
    }
}
