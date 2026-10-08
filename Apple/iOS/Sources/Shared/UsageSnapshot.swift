import Foundation

// MARK: - 小组件共享快照（主 App 刷新后写入 App Group 容器，Widget 读取展示）

struct QuotaWindowSnapshot: Codable, Equatable {
    var label: String
    var percentage: Double
    var resetDate: Date?
}

struct AccountUsageSnapshot: Codable, Equatable {
    var accountID: UUID
    var displayName: String
    var shortLabel: String
    var tintHex: String
    var level: String?
    var windows: [QuotaWindowSnapshot]
    var balanceText: String?
    var hasError: Bool
    var updatedAt: Date

    /// 当前最紧的配额窗口（百分比最高），纯余额账号为 nil
    var criticalWindow: QuotaWindowSnapshot? {
        windows.max(by: { $0.percentage < $1.percentage })
    }
}

struct UsageSnapshotFile: Codable {
    var updatedAt: Date
    var accounts: [AccountUsageSnapshot]
}

enum UsageSnapshotStore {
    static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("usage-snapshot.json")
    }

    static func save(_ snapshot: UsageSnapshotFile) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> UsageSnapshotFile? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshotFile.self, from: data)
    }
}
