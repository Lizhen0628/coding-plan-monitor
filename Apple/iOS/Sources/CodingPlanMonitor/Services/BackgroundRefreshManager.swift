import Foundation
import BackgroundTasks

/// 后台静默刷新：让阈值/重置通知在 App 未打开时也能触发。
/// 注意：实际执行频率由系统调度（通常不早于设置的间隔），模拟器可用
/// `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"…"]` 调试。
enum BackgroundRefreshManager {
    static let taskIdentifier = "com.lizhen.CodingPlanMonitor.refresh"
    /// 系统对 BGAppRefreshTask 的实际下限约 15 分钟
    private static let minimumInterval: TimeInterval = 15 * 60

    /// 必须在 App 启动完成前注册
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()

            // BGAppRefreshTask 非 Sendable，用 unchecked 包装传入并发域（同一任务实例仅在两处串行访问）
            let box = UnsafeTaskBox(task)
            let work = Task { @MainActor in
                await MonitorViewModel.current?.refresh()
                box.task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                box.task.setTaskCompleted(success: false)
            }
        }
    }

    private struct UnsafeTaskBox: @unchecked Sendable {
        let task: BGAppRefreshTask
        init(_ task: BGAppRefreshTask) { self.task = task }
    }

    /// 按设置的刷新间隔排下一次后台任务
    static func schedule() {
        let minutes = UserDefaults.standard.integer(forKey: "refreshMinutes")
        let interval = max(TimeInterval((minutes > 0 ? minutes : 5) * 60), minimumInterval)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
