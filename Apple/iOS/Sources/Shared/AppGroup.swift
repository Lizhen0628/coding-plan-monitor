import Foundation

/// App Group：主 App 与小组件共享用量快照
enum AppGroup {
    static let identifier = "group.com.lizhen.CodingPlanMonitor"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
