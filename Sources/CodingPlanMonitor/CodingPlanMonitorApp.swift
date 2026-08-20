import SwiftUI
import AppKit
import Combine

@main
struct CodingPlanMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.vm)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm = MonitorViewModel()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Coding Plan Monitor")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item

        // 从菜单栏图标正下方展开的 popover（带箭头，点击外部自动收起）
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: PanelView().environmentObject(vm)
        )
        self.popover = popover

        // 菜单栏文本跟随数据变化
        observer = vm.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
        updateTitle()

        // 启动时先拉一次数据，让菜单栏尽快显示百分比
        Task { await vm.refresh() }
    }

    private func updateTitle() {
        statusItem?.button?.title = vm.menuBarTitle
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
