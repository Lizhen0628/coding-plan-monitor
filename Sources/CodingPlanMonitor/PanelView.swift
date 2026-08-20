import SwiftUI
import AppKit

struct PanelView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @Environment(\.openSettings) private var openSettings

    private var autoRefresh: Timer.TimerPublisher {
        Timer.publish(every: TimeInterval(vm.refreshMinutes * 60), on: .main, in: .common)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)

            if vm.configuredProviders.isEmpty {
                emptyState
            } else {
                ForEach(vm.configuredProviders, id: \.self) { provider in
                    ProviderSection(provider: provider)
                    if provider != vm.configuredProviders.last {
                        Divider().padding(.vertical, 8)
                    }
                }
            }

            Divider().padding(.vertical, 8)
            statusRow
            Divider().padding(.vertical, 8)
            actionButtons
        }
        .padding(12)
        .frame(width: 320)
        .task { await vm.refresh() }
        .onReceive(autoRefresh.autoconnect()) { _ in
            Task { await vm.refresh() }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Coding Plan Monitor")
                .font(.headline)
            Spacer()
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: - 状态行

    private var statusRow: some View {
        HStack {
            if let last = vm.lastRefresh {
                Text("上次刷新 \(last.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Text("尚未刷新")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            Circle()
                .fill(vm.isOnline ? Color.green : (vm.lastRefresh != nil ? Color.red : Color.gray))
                .frame(width: 8, height: 8)
            Text(vm.isOnline ? "在线" : (vm.lastRefresh != nil ? "异常" : "未知"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: 2) {
            ActionRow(title: "手动刷新", icon: "arrow.clockwise", shortcut: "⌘R") {
                Task { await vm.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)

            ActionRow(title: "设置…", icon: "gearshape", shortcut: "⌘,") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            ActionRow(title: "退出 Coding Plan Monitor", icon: "power", shortcut: "⌘Q", tint: .red) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("尚未配置 API Key")
                .font(.callout)
            Button("打开设置…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - 供应商区块

private struct ProviderSection: View {
    @EnvironmentObject private var vm: MonitorViewModel
    let provider: Provider

    private var usage: ProviderUsage? { vm.usages[provider] }
    private var error: String? { vm.errors[provider] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 供应商标题 + 套餐等级
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.displayName)
                    .font(.callout.weight(.semibold))
                if let level = usage?.level, !level.isEmpty {
                    Text("· \(level.uppercased())")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                PercentageRow(
                    icon: "clock",
                    title: "5 小时额度",
                    percentage: usage?.fiveHour?.percentage,
                    subtitle: vm.fiveHourSubtitle(usage?.fiveHour),
                    onToggle: { vm.showCountdown.toggle() }
                )
                if let weekly = usage?.weekly {
                    PercentageRow(
                        icon: "calendar",
                        title: "每周额度",
                        percentage: weekly.percentage,
                        subtitle: vm.weeklySubtitle(weekly),
                        onToggle: { vm.showCountdown.toggle() }
                    )
                }
                if let mcp = usage?.mcp {
                    MCPRow(usage: mcp)
                }
            }
        }
    }
}

// MARK: - 百分比额度行

private struct PercentageRow: View {
    let icon: String
    let title: String
    let percentage: Double?
    let subtitle: String
    let onToggle: () -> Void

    private var tint: Color {
        guard let p = percentage else { return .accentColor }
        if p >= 80 { return .red }
        if p >= 50 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.callout.weight(.medium))
                Spacer()
                if let p = percentage {
                    Text("\(Int(p))%")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: percentage ?? 0, total: 100)
                .tint(tint)
            if !subtitle.isEmpty {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Text(subtitle)
                        Text("（点击切换）")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - MCP 月度行

private struct MCPRow: View {
    let usage: MCPUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("MCP 每月", systemImage: "shield")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(usage.used.formatted()) / \(usage.total.formatted()) 次")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("剩余 \(usage.remaining.formatted()) 次")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 操作行

private struct ActionRow: View {
    let title: String
    let icon: String
    let shortcut: String
    var tint: Color = .primary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
