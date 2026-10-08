import ActivityKit
import Foundation

/// Live Activity：配额 ≥90% 时锁屏/灵动岛常驻倒计时。
/// 主 App 与 Widget 扩展共用此定义（各自编译一份）。
struct QuotaActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var accountName: String
        var shortLabel: String
        var tintHex: String
        var windowLabel: String
        var percentage: Double
        var resetDate: Date?
    }

    /// 活动唯一键：账号ID-窗口标签，用于更新/结束对应的活动
    var key: String
}
