import SwiftUI

@main
struct CodingPlanMonitorApp: App {
    @StateObject private var vm = MonitorViewModel()

    init() {
        // 后台任务必须在启动完成前注册
        BackgroundRefreshManager.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .task {
                    await NotificationManager.requestAuthorizationIfNeeded()
                    BackgroundRefreshManager.schedule()
                }
        }
    }
}

enum AppTab: Hashable {
    case usage
    case accounts
}

struct RootView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @State private var selection: AppTab = .usage

    var body: some View {
        TabView(selection: $selection) {
            UsageView(openAccounts: { selection = .accounts })
                .tabItem { Label("用量", systemImage: "gauge.with.needle") }
                .tag(AppTab.usage)

            AccountsView()
                .tabItem { Label("账号", systemImage: "key") }
                .tag(AppTab.accounts)
        }
        .tint(.accentColor)
    }
}
