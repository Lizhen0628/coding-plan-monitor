import SwiftUI
import AppKit

struct PanelView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @Environment(\.openSettings) private var openSettings
    /// 已展开详情的账号（默认展开第一个，错误账号自动展开）
    @State private var expandedIDs: Set<UUID> = []
    /// 正在拖拽的账号（拖动排序用）
    @State private var draggedID: UUID?

    private var autoRefresh: Timer.TimerPublisher {
        Timer.publish(every: TimeInterval(vm.refreshMinutes * 60), on: .main, in: .common)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if vm.monitoredAccounts.isEmpty {
                Divider().padding(.vertical, 8)
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(vm.monitoredAccounts) { account in
                            AccountRow(
                                account: account,
                                expanded: expandedIDs.contains(account.id),
                                onToggle: { toggle(account.id) }
                            )
                            .opacity(draggedID == account.id ? 0.4 : 1)
                            .onDrag {
                                draggedID = account.id
                                return NSItemProvider(object: account.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: AccountDropDelegate(
                                    target: account,
                                    vm: vm,
                                    draggedID: $draggedID
                                )
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: maxListHeight)
            }

            Divider().padding(.vertical, 8)
            statusRow
            Divider().padding(.vertical, 8)
            actionButtons
        }
        .padding(12)
        .frame(width: 340)
        .task { await vm.refresh() }
        .onReceive(autoRefresh.autoconnect()) { _ in
            Task { await vm.refresh() }
        }
        .onAppear {
            if expandedIDs.isEmpty, let first = vm.monitoredAccounts.first {
                expandedIDs.insert(first.id)
            }
        }
        .onChange(of: vm.errors) {
            // 出错账号自动展开，让错误信息可见
            for id in vm.errors.keys { expandedIDs.insert(id) }
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }

    /// 账号列表最大高度：随屏幕可见高度调整，
    /// 头部/状态栏/按钮区约 180pt，底部留边距，防止展开过多时超出屏幕
    private var maxListHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(200, min(520, screenHeight - 220))
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
            Text("尚未添加账号")
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

// MARK: - 账号行（紧凑摘要 + 点击展开详情）

private struct AccountRow: View {
    @EnvironmentObject private var vm: MonitorViewModel
    let account: Account
    let expanded: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    private var usage: ProviderUsage? { vm.usages[account.id] }
    private var error: String? { vm.errors[account.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 摘要行（始终可见）
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ProviderBadge(provider: account.provider)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.displayName(for: account))
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if let level = usage?.level, !level.isEmpty {
                            Text("\(account.provider.displayName) · \(level.uppercased())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(account.provider.displayName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 4)

                    if error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    } else if let usage {
                        if let fiveHour = usage.fiveHour {
                            MiniMeter(label: "5小时", percentage: fiveHour.percentage)
                        }
                        if let weekly = usage.weekly {
                            MiniMeter(label: "每周", percentage: weekly.percentage)
                        }
                        if let monthly = usage.monthly {
                            MiniMeter(label: "每月", percentage: monthly.percentage)
                        }
                        ForEach(usage.extras, id: \.label) { extra in
                            MiniMeter(label: extra.label, percentage: extra.percentage)
                        }
                        if let balance = usage.balance {
                            MiniBalance(symbol: balance.symbol, total: balance.total)
                        }
                    } else {
                        MiniMeter(label: "5小时", percentage: nil)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(hovering || expanded ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            // 展开的详情
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        if usage?.fiveHour != nil || usage == nil {
                            PercentageRow(
                                icon: "clock",
                                title: "5 小时额度",
                                percentage: usage?.fiveHour?.percentage,
                                subtitle: vm.fiveHourSubtitle(usage?.fiveHour, key: "\(account.id.uuidString)-fiveHour"),
                                onToggle: { vm.toggleCountdown("\(account.id.uuidString)-fiveHour") }
                            )
                        }
                        if let weekly = usage?.weekly {
                            PercentageRow(
                                icon: "calendar",
                                title: "每周额度",
                                percentage: weekly.percentage,
                                subtitle: vm.weeklySubtitle(weekly, key: "\(account.id.uuidString)-weekly"),
                                onToggle: { vm.toggleCountdown("\(account.id.uuidString)-weekly") }
                            )
                        }
                        if let monthly = usage?.monthly {
                            PercentageRow(
                                icon: "calendar.badge.clock",
                                title: "每月总额度",
                                percentage: monthly.percentage,
                                subtitle: "",
                                onToggle: {}
                            )
                        }
                        ForEach(usage?.extras ?? [], id: \.label) { extra in
                            PercentageRow(
                                icon: "sparkles",
                                title: extra.label,
                                percentage: extra.percentage,
                                subtitle: "",
                                onToggle: {}
                            )
                        }
                        if let balance = usage?.balance {
                            BalanceRow(balance: balance)
                        }
                        if let mcp = usage?.mcp {
                            MCPRow(usage: mcp)
                        }
                    }
                }
                .padding(.leading, 38)
                .padding(.trailing, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 迷你额度表（收起状态下的一览）

private struct MiniMeter: View {
    let label: String
    let percentage: Double?

    private var tint: Color {
        guard let p = percentage else { return .secondary }
        if p >= 80 { return .red }
        if p >= 50 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 2) {
            if let p = percentage {
                Text("\(Int(p))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            } else {
                Text("--")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            ProgressView(value: percentage ?? 0, total: 100)
                .tint(tint)
                .frame(width: 34)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 迷你余额（收起状态）

private struct MiniBalance: View {
    let symbol: String
    let total: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("\(symbol)\(total, specifier: "%.2f")")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(total > 0 ? Color.accentColor : Color.red)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 34)
            // 与 MiniMeter 的进度条占位对齐
            ProgressView(value: 0, total: 100).hidden()
                .frame(width: 34)
            Text("余额")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }
}

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

// MARK: - 账户余额行

private struct BalanceRow: View {
    let balance: BalanceInfo

    var body: some View {
        HStack(spacing: 8) {
            Label("账户余额", systemImage: "creditcard")
                .font(.callout)
            Spacer()
            if balance.granted > 0 {
                Text("含赠送 \(balance.symbol)\(balance.granted, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(balance.symbol)\(balance.total, specifier: "%.2f")")
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(balance.total > 0 ? .primary : Color.red)
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
