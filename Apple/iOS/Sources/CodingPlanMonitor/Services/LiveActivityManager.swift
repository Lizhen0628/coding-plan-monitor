import ActivityKit
import Foundation

/// Live Activity 生命周期：每次刷新后同步超过阈值的配额窗口。
/// 窗口回到阈值以下或重置后，对应活动自动结束。
@MainActor
enum LiveActivityManager {
    /// UserDefaults 键：灵动岛触发阈值（百分比），100 = 关闭
    static let thresholdDefaultsKey = "liveActivityThreshold"

    private static var threshold: Double {
        guard let stored = UserDefaults.standard.object(forKey: thresholdDefaultsKey) as? Double else { return 90 }
        // 旧版 Picker 用 0 表示关闭，映射到 100
        return stored == 0 ? 100 : stored
    }

    static func sync(
        accounts: [Account],
        usages: [UUID: ProviderUsage],
        displayName: (Account) -> String
    ) {
        // 跟随「额度提醒」与阈值开关；关闭时清理所有活动
        guard NotificationManager.isEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }
        let threshold = threshold
        guard threshold < 100 else {
            endAll()
            return
        }

        var activeKeys: Set<String> = []

        for account in accounts {
            guard let usage = usages[account.id] else { continue }
            for window in quotaWindows(of: usage) where window.percentage >= threshold {
                let key = "\(account.id)-\(window.label)"
                activeKeys.insert(key)

                let state = QuotaActivityAttributes.ContentState(
                    accountName: displayName(account),
                    shortLabel: account.provider.shortLabel,
                    tintHex: account.provider.tintHex,
                    windowLabel: window.label,
                    percentage: window.percentage,
                    resetDate: window.resetDate
                )

                if let activity = Activity<QuotaActivityAttributes>.activities.first(where: { $0.attributes.key == key }) {
                    let box = UnsafeActivityBox(activity)
                    Task {
                        await box.activity.update(.init(state: state, staleDate: window.resetDate))
                    }
                } else {
                    let attributes = QuotaActivityAttributes(key: key)
                    _ = try? Activity<QuotaActivityAttributes>.request(
                        attributes: attributes,
                        content: .init(state: state, staleDate: window.resetDate),
                        pushType: nil
                    )
                }
            }
        }

        // 已回落/已重置/已删除的窗口：结束对应活动
        for activity in Activity<QuotaActivityAttributes>.activities where !activeKeys.contains(activity.attributes.key) {
            let box = UnsafeActivityBox(activity)
            Task { await box.activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func endAll() {
        for activity in Activity<QuotaActivityAttributes>.activities {
            let box = UnsafeActivityBox(activity)
            Task { await box.activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Activity 非 Sendable，包装后传入并发域（实例仅在单一 Task 中访问）
    private struct UnsafeActivityBox: @unchecked Sendable {
        let activity: Activity<QuotaActivityAttributes>
        init(_ activity: Activity<QuotaActivityAttributes>) { self.activity = activity }
    }

    private static func quotaWindows(of usage: ProviderUsage) -> [(label: String, percentage: Double, resetDate: Date?)] {
        var result: [(label: String, percentage: Double, resetDate: Date?)] = []
        if let window = usage.fiveHour { result.append(("5小时", window.percentage, window.resetDate)) }
        if let window = usage.weekly { result.append(("每周", window.percentage, window.resetDate)) }
        if let window = usage.monthly { result.append(("每月", window.percentage, window.resetDate)) }
        for extra in usage.extras { result.append((extra.label, extra.percentage, extra.resetDate)) }
        return result
    }
}
