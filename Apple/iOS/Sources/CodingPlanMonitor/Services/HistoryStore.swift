import Foundation

struct HistoryPoint: Codable, Equatable {
    var date: Date
    var percentage: Double
}

/// 用量历史：每次刷新记录一条快照，供展开详情里的趋势 sparkline 使用。
/// 存储在 Application Support（无需进 App Group，小组件不看历史）。
@MainActor
enum HistoryStore {
    /// 单序列最多保留 200 点（按 5 分钟刷新约覆盖 16 小时，按 15 分钟约 2 天）
    private static let maxPointsPerSeries = 200
    /// 同一序列最短记录间隔；间隔内的刷新只更新最新点的值
    private static let minRecordInterval: TimeInterval = 10 * 60

    private static var cache: [String: [HistoryPoint]] = loadFromDisk()

    static func record(accountID: UUID, label: String, percentage: Double, at date: Date = .now) {
        let key = key(accountID, label)
        var series = cache[key] ?? []
        if let last = series.last, date.timeIntervalSince(last.date) < minRecordInterval {
            series[series.count - 1] = HistoryPoint(date: date, percentage: percentage)
        } else {
            series.append(HistoryPoint(date: date, percentage: percentage))
        }
        if series.count > maxPointsPerSeries {
            series.removeFirst(series.count - maxPointsPerSeries)
        }
        cache[key] = series
    }

    static func series(for accountID: UUID, label: String) -> [HistoryPoint] {
        cache[key(accountID, label)] ?? []
    }

    static func remove(accountID: UUID) {
        let prefix = accountID.uuidString
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        persist()
    }

    /// 每次刷新记录完所有序列后统一落盘
    static func persist() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func key(_ accountID: UUID, _ label: String) -> String {
        "\(accountID.uuidString)-\(label)"
    }

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("usage-history.json")
    }

    private static func loadFromDisk() -> [String: [HistoryPoint]] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [HistoryPoint]].self, from: data)) ?? [:]
    }
}
