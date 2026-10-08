import Foundation
import UserNotifications

/// 用量提醒：阈值告警（80% / 95%，每个重置周期只发一次）+ 重置完成定时通知
@MainActor
enum NotificationManager {
    static let enabledDefaultsKey = "usageAlertsEnabled"
    private static let notifiedDefaultsKey = "notifiedThresholdKeys"
    /// 处于余额预警状态的账号（回升后解除，避免重复轰炸）
    private static let balanceAlertsDefaultsKey = "activeBalanceAlerts"
    private static let weeklyReportIdentifier = "weekly-report"
    /// 只保留最近的去重记录，避免无限增长
    private static let maxNotifiedRecords = 300

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    /// 首次启动时请求通知权限（已决定过则直接返回）
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// 每次刷新完成后调用：评估阈值、重排重置提醒
    static func evaluate(
        accounts: [Account],
        usages: [UUID: ProviderUsage],
        displayName: (Account) -> String
    ) {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()

        // 重置提醒全部重排（账号/重置时间可能已变化）
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix("reset-") }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedDefaultsKey) ?? [])
        var notifiedChanged = false

        for account in accounts {
            guard let usage = usages[account.id] else { continue }
            let name = displayName(account)

            for window in quotaWindows(of: usage) {
                // 阈值告警：同一重置周期内同一档只提醒一次
                for threshold in [80.0, 95.0] where window.percentage >= threshold {
                    let key = "\(account.id)-\(window.label)-\(Int(threshold))-\(Int(window.resetDate?.timeIntervalSince1970 ?? 0))"
                    guard !notified.contains(key) else { continue }
                    notified.insert(key)
                    notifiedChanged = true

                    let content = UNMutableNotificationContent()
                    content.title = "\(name) 额度告急"
                    var body = "\(window.label)额度已用 \(Int(window.percentage))%"
                    if let resetDate = window.resetDate {
                        body += "，\(resetDate.formatted(date: .omitted, time: .shortened)) 重置"
                    }
                    content.body = body
                    content.sound = .default
                    center.add(UNNotificationRequest(identifier: "threshold-\(key)", content: content, trigger: nil))
                }

                // 重置完成提醒：到点推送（仅排未来 7 天内的）
                if let resetDate = window.resetDate {
                    let interval = resetDate.timeIntervalSinceNow
                    guard interval > 60, interval < 7 * 86400 else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "\(name) 额度已重置"
                    content.body = "\(window.label)额度已恢复，继续加油"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    center.add(UNNotificationRequest(
                        identifier: "reset-\(account.id)-\(window.label)",
                        content: content,
                        trigger: trigger
                    ))
                }
            }
        }

        if notifiedChanged {
            if notified.count > maxNotifiedRecords {
                notified = Set(notified.sorted().suffix(maxNotifiedRecords))
            }
            UserDefaults.standard.set(Array(notified), forKey: notifiedDefaultsKey)
        }

        evaluateBalanceAlerts(accounts: accounts, usages: usages, displayName: displayName, center: center)
        scheduleWeeklyReport(accounts: accounts, displayName: displayName, center: center)
    }

    // MARK: - 余额预警（DeepSeek 等按量计费平台）

    /// 各币种的预警阈值
    private static func balanceThreshold(currency: String) -> Double {
        switch currency.uppercased() {
        case "USD", "EUR": return 2
        default: return 10 // CNY 等
        }
    }

    /// 余额跌破阈值时告警一次，回升后解除
    private static func evaluateBalanceAlerts(
        accounts: [Account],
        usages: [UUID: ProviderUsage],
        displayName: (Account) -> String,
        center: UNUserNotificationCenter
    ) {
        var active = Set(UserDefaults.standard.stringArray(forKey: balanceAlertsDefaultsKey) ?? [])
        var changed = false

        for account in accounts {
            guard let balance = usages[account.id]?.balance else { continue }
            let key = "balance-\(account.id)"
            if balance.total <= balanceThreshold(currency: balance.currency) {
                guard !active.contains(key) else { continue }
                active.insert(key)
                changed = true

                let content = UNMutableNotificationContent()
                content.title = "\(displayName(account)) 余额不足"
                content.body = "余额仅剩 \(balance.symbol)\(String(format: "%.2f", balance.total))，充值后自动解除提醒"
                content.sound = .default
                center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
            } else if active.contains(key) {
                active.remove(key)
                changed = true
            }
        }

        if changed {
            UserDefaults.standard.set(Array(active), forKey: balanceAlertsDefaultsKey)
        }
    }

    // MARK: - 周用量报告（每周一 09:00，正文取自近 7 天历史峰值）

    private static func scheduleWeeklyReport(
        accounts: [Account],
        displayName: (Account) -> String,
        center: UNUserNotificationCenter
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [weeklyReportIdentifier])
        guard !accounts.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "本周用量报告"
        content.body = weeklySummary(accounts: accounts, displayName: displayName)
        content.sound = .default

        var components = DateComponents()
        components.weekday = 2 // 周一
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: weeklyReportIdentifier, content: content, trigger: trigger))
    }

    /// 近 7 天各账号各窗口的峰值 Top 2；无历史时给温和文案
    private static func weeklySummary(accounts: [Account], displayName: (Account) -> String) -> String {
        let weekAgo = Date.now.addingTimeInterval(-7 * 86400)
        var peaks: [(name: String, label: String, peak: Double)] = []
        for account in accounts {
            for label in ["5小时", "每周", "每月"] {
                let series = HistoryStore.series(for: account.id, label: label).filter { $0.date >= weekAgo }
                guard let peak = series.map(\.percentage).max() else { continue }
                peaks.append((displayName(account), label, peak))
            }
        }
        peaks.sort { $0.peak > $1.peak }
        let top = peaks.prefix(2)
        guard !top.isEmpty else {
            return "本周各账号额度都很充裕，继续保持节奏。"
        }
        return top.map { "\($0.name) \($0.label)峰值 \(Int($0.peak))%" }.joined(separator: "；") + "。张弛有度，新的一周加油。"
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
