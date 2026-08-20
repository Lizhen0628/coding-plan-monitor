import SwiftUI

@main
struct CodingPlanMonitorApp: App {
    @StateObject private var vm = MonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(vm)
        } label: {
            Label(vm.menuBarTitle, systemImage: "gauge.with.needle")
                .task { await vm.refresh() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(vm)
        }
    }
}
