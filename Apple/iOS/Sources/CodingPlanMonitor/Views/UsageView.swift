import SwiftUI
import UIKit

struct UsageView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    let openAccounts: () -> Void

    /// 已展开详情的账号（默认展开第一个，错误账号自动展开）
    @State private var expandedIDs: Set<UUID> = []
    @State private var editingAccount: Account?
    @State private var shareImage: ShareCardImage?
    @State private var deleteCandidate: Account?

    var body: some View {
        NavigationStack {
            Group {
                if vm.monitoredAccounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("用量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            preview: SharePreview("Coding 额度报告", image: shareImage.previewImage)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(vm.isLoading || vm.monitoredAccounts.isEmpty)
                }
            }
            .sheet(item: $editingAccount) { account in
                AccountEditView(existing: account)
                    .environmentObject(vm)
                    .interactiveDismissDisabled()
            }
            .confirmationDialog(
                "确定删除「\(deleteCandidate.map { vm.displayName(for: $0) } ?? "")」吗？",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除账号", role: .destructive) {
                    if let account = deleteCandidate {
                        vm.removeAccount(account)
                    }
                    deleteCandidate = nil
                }
                Button("取消", role: .cancel) {
                    deleteCandidate = nil
                }
            } message: {
                Text("删除后该账号的凭证与用量历史会一并清除")
            }
        }
        .task { await vm.refresh() }
        .onReceive(autoRefreshPublisher) { _ in
            Task { await vm.refresh() }
        }
        .onChange(of: vm.errors) { _, errors in
            // 出错账号自动展开，让错误信息可见
            for id in errors.keys { expandedIDs.insert(id) }
        }
        .onAppear {
            if expandedIDs.isEmpty, let first = vm.monitoredAccounts.first {
                expandedIDs.insert(first.id)
            }
            rebuildShareImage()
        }
        .onChange(of: vm.lastRefresh) { _, _ in
            rebuildShareImage()
        }
    }

    /// 刷新后重渲染分享卡片（无用量数据时隐藏分享按钮）
    private func rebuildShareImage() {
        shareImage = ShareCardRenderer.render(items: shareItems(), date: vm.lastRefresh ?? .now)
    }

    /// 分享卡片内容：按最紧配额排序取前 4 个账号
    private func shareItems() -> [ShareAccountItem] {
        let items: [ShareAccountItem] = vm.monitoredAccounts.compactMap { account in
            guard let usage = vm.usages[account.id] else { return nil }
            var windows: [(label: String, percentage: Double)] = []
            if let window = usage.fiveHour { windows.append(("5小时", window.percentage)) }
            if let window = usage.weekly { windows.append(("每周", window.percentage)) }
            if let window = usage.monthly { windows.append(("每月", window.percentage)) }
            for extra in usage.extras { windows.append((extra.label, extra.percentage)) }
            let critical = windows.max(by: { $0.percentage < $1.percentage })
            var balanceText: String?
            if let balance = usage.balance {
                balanceText = "\(balance.symbol)\(String(format: "%.2f", balance.total))"
            }
            return ShareAccountItem(
                name: vm.displayName(for: account),
                shortLabel: account.provider.shortLabel,
                tint: account.provider.tint,
                ringPercentage: critical?.percentage,
                ringLabel: critical?.label,
                balanceText: balanceText
            )
        }
        return Array(items.sorted { ($0.ringPercentage ?? -1) > ($1.ringPercentage ?? -1) }.prefix(4))
    }

    /// 自动刷新定时器（refreshMinutes 变化时随 body 重建）
    private var autoRefreshPublisher: Timer.TimerPublisher {
        Timer.publish(every: TimeInterval(vm.refreshMinutes * 60), on: .main, in: .common)
    }

    // MARK: - 账号列表

    private var accountList: some View {
        List {
            heroCard
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(vm.monitoredAccounts) { account in
                AccountCard(
                    account: account,
                    expanded: expandedIDs.contains(account.id),
                    onToggle: { toggle(account.id) },
                    onEdit: { editingAccount = account }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteCandidate = account
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        editingAccount = account
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }

            statusRow
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.refresh() }
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

    // MARK: - 健康摘要（首屏视觉锚点）

    /// ≥80% 的配额窗口数量
    private var urgentCount: Int {
        vm.monitoredAccounts.reduce(0) { count, account in
            guard let usage = vm.usages[account.id] else { return count }
            var percentages = [usage.fiveHour?.percentage, usage.weekly?.percentage, usage.monthly?.percentage].compactMap { $0 }
            percentages += usage.extras.map(\.percentage)
            return count + percentages.filter { $0 >= 80 }.count
        }
    }

    /// 未来最近的一次重置
    private var nextReset: (account: String, label: String, date: Date)? {
        var best: (String, String, Date)?
        for account in vm.monitoredAccounts {
            guard let usage = vm.usages[account.id] else { continue }
            var windows: [(String, Date?)] = [
                ("5小时", usage.fiveHour?.resetDate),
                ("每周", usage.weekly?.resetDate),
                ("每月", usage.monthly?.resetDate),
            ]
            windows += usage.extras.map { ($0.label, $0.resetDate) }
            for (label, date) in windows {
                guard let date, date > .now else { continue }
                if best == nil || date < best!.2 {
                    best = (vm.displayName(for: account), label, date)
                }
            }
        }
        return best
    }

    private var heroCard: some View {
        let errorCount = vm.errors.count
        let urgent = urgentCount
        let title: String
        let subtitle: String
        let icon: String
        if errorCount > 0 {
            title = "\(errorCount) 个账号异常"
            subtitle = "\(vm.monitoredAccounts.count) 个订阅监控中"
            icon = "exclamationmark.triangle.fill"
        } else if urgent > 0 {
            title = "\(urgent) 个配额告急"
            subtitle = "\(vm.monitoredAccounts.count) 个订阅监控中"
            icon = "gauge.with.needle"
        } else {
            title = "额度健康"
            subtitle = "\(vm.monitoredAccounts.count) 个订阅 · 全部正常"
            icon = "checkmark.shield.fill"
        }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.75)
                    Text(title)
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .opacity(0.9)
            }

            if let next = nextReset {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Group {
                        Text("最近的重置：\(next.account) \(next.label) · ") +
                        Text(next.date, style: .relative)
                    }
                    .font(.caption)
                    .opacity(0.9)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [.indigo, Color(red: 0.31, green: 0.27, blue: 0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: .indigo.opacity(0.25), radius: 16, x: 0, y: 8)
    }

    // MARK: - 状态行

    private var statusRow: some View {
        HStack(spacing: 6) {
            if let last = vm.lastRefresh {
                Text("上次刷新 \(last.formatted(date: .omitted, time: .standard))")
            } else {
                Text("尚未刷新")
            }
            Spacer()
            Circle()
                .fill(vm.isOnline ? Color.green : (vm.lastRefresh != nil ? Color.red : Color.gray))
                .frame(width: 8, height: 8)
            Text(vm.isOnline ? "在线" : (vm.lastRefresh != nil ? "异常" : "未知"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    // MARK: - 空态（引导机会：价值说明 + 安全感文案 + 拇指区 CTA）

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .frame(width: 96, height: 96)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .accentColor.opacity(0.18), radius: 16, x: 0, y: 8)
            Text("把 Coding 额度装进口袋")
                .font(.headline)
                .padding(.top, 24)
            Text("添加 GLM、Kimi、Claude 等订阅的凭证，\n随时查看 5 小时 / 每周 / 每月额度与重置时间")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)
            Button {
                openAccounts()
            } label: {
                Label("添加第一个账号", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 40)
            Text("凭证仅保存在本机，只用于查询用量")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            Spacer()
            statusRow
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - 账号卡片（每卡一个主角：最紧配额圆环 + 其余降级 chip）

struct AccountCard: View {
    @EnvironmentObject private var vm: MonitorViewModel
    let account: Account
    let expanded: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var usage: ProviderUsage? { vm.usages[account.id] }
    private var error: String? { vm.errors[account.id] }

    /// 该账号的全部配额窗口
    private var windows: [(label: String, percentage: Double, resetDate: Date?)] {
        guard let usage else { return [] }
        var result: [(label: String, percentage: Double, resetDate: Date?)] = []
        if let window = usage.fiveHour { result.append(("5小时", window.percentage, window.resetDate)) }
        if let window = usage.weekly { result.append(("每周", window.percentage, window.resetDate)) }
        if let window = usage.monthly { result.append(("每月", window.percentage, window.resetDate)) }
        for extra in usage.extras { result.append((extra.label, extra.percentage, extra.resetDate)) }
        return result
    }

    /// 最紧的窗口（百分比最高），作为卡片主角
    private var criticalIndex: Int? {
        guard !windows.isEmpty else { return nil }
        return windows.indices.max(by: { windows[$0].percentage < windows[$1].percentage })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                summary
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                detail
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: 摘要

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProviderBadge(provider: account.provider, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.displayName(for: account))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                trailing
            }

            // 收起态同时展示各配额窗口（5小时/每周/每月）与 MCP 工具调用的迷你圆环；展开后由详情行呈现，不再重复
            if error == nil && !windows.isEmpty && !expanded {
                HStack(spacing: 20) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        VStack(spacing: 4) {
                            QuotaRing(
                                percentage: window.percentage,
                                tint: StatusColor.forPercentage(window.percentage),
                                size: 40
                            )
                            Text(window.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let mcp = usage?.mcp, mcp.total > 0 {
                        let percentage = Double(mcp.used) / Double(mcp.total) * 100
                        VStack(spacing: 4) {
                            QuotaRing(
                                percentage: percentage,
                                tint: StatusColor.forPercentage(percentage),
                                size: 40
                            )
                            Text("MCP")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !chips.isEmpty && !expanded {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.text) { chip in
                        StatusChip(text: chip.text, tint: chip.tint)
                    }
                }
            }
        }
    }

    private var caption: String {
        if error != nil { return "凭证或网络异常" }
        var parts = [account.provider.displayName]
        if let level = usage?.level, !level.isEmpty {
            parts.append(level.uppercased())
        }
        if let index = criticalIndex, let resetDate = windows[index].resetDate {
            parts.append(resetCaption(resetDate))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if error != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        } else if windows.isEmpty, let balance = usage?.balance {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(balance.symbol)\(balance.total, specifier: "%.2f")")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(balance.total > 0 ? Color.accentColor : Color.red)
                if balance.granted > 0 {
                    Text("含赠送 \(balance.symbol)\(balance.granted, specifier: "%.2f")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if !windows.isEmpty {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        } else {
            Text("--")
                .font(.headline)
                .foregroundStyle(.tertiary)
        }
    }

    /// 次级信息 chip（余额），配额窗口与 MCP 已由圆环展示
    private var chips: [(text: String, tint: Color)] {
        guard error == nil else { return [] }
        var result: [(text: String, tint: Color)] = []
        if let balance = usage?.balance, !windows.isEmpty {
            result.append(("余额 \(balance.symbol)\(String(format: "%.2f", balance.total))", balance.total > 0 ? .secondary : .red))
        }
        return result
    }

    // MARK: 展开详情

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error {
                errorDetail(error)
            } else {
                detailRows
            }

            Divider()
                .padding(.vertical, 12)
            CopyKeyRow(label: account.provider.credentialLabels.primary, key: account.apiKey)
            if let secondaryLabel = account.provider.credentialLabels.secondary,
               !account.secretKey.isEmpty {
                CopyKeyRow(label: secondaryLabel, key: account.secretKey)
            }
        }
    }

    /// 错误态：给解决路径，不只报错
    private func errorDetail(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onEdit) {
                Text("更新凭证")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(height: 36)
                    .padding(.horizontal, 16)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var detailRows: some View {
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
            rowDivider
            PercentageRow(
                icon: "calendar",
                title: "每周额度",
                percentage: weekly.percentage,
                subtitle: vm.weeklySubtitle(weekly, key: "\(account.id.uuidString)-weekly"),
                onToggle: { vm.toggleCountdown("\(account.id.uuidString)-weekly") }
            )
        }
        if let monthly = usage?.monthly {
            rowDivider
            PercentageRow(
                icon: "calendar.badge.clock",
                title: "每月总额度",
                percentage: monthly.percentage,
                subtitle: "",
                onToggle: {}
            )
        }
        ForEach(usage?.extras ?? [], id: \.label) { extra in
            rowDivider
            PercentageRow(
                icon: "sparkles",
                title: extra.label,
                percentage: extra.percentage,
                subtitle: "",
                onToggle: {}
            )
        }
        if let balance = usage?.balance {
            rowDivider
            BalanceRow(balance: balance)
        }
        if let mcp = usage?.mcp {
            rowDivider
            MCPRow(usage: mcp)
        }
    }

    private var rowDivider: some View {
        Divider().opacity(0.5)
    }
}

// MARK: - 百分比行（大数字 + 圆头进度条 + 趋势 + 可切换倒计时）

struct PercentageRow: View {
    let icon: String
    let title: String
    let percentage: Double?
    let subtitle: String
    let onToggle: () -> Void

    private var tint: Color {
        StatusColor.forPercentage(percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let p = percentage {
                    Text("\(String(format: "%.1f", p))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(tint)
                } else {
                    Text("--")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(max(percentage ?? 0, 0), 100)) / 100)
                }
            }
            .frame(height: 6)

            if !subtitle.isEmpty {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Text(subtitle)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - MCP 月度行（百分比 + 进度条 + 趋势）

struct MCPRow: View {
    let usage: MCPUsage

    private var percentage: Double {
        guard usage.total > 0 else { return 0 }
        return Double(usage.used) / Double(usage.total) * 100
    }

    private var tint: Color {
        StatusColor.forPercentage(percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("MCP 每月", systemImage: "shield")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(String(format: "%.1f", percentage))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(max(percentage, 0), 100)) / 100)
                }
            }
            .frame(height: 6)

            Text("已用 \(usage.used.formatted()) / \(usage.total.formatted()) 次 · 剩余 \(usage.remaining.formatted()) 次")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - 账户余额行

struct BalanceRow: View {
    let balance: BalanceInfo

    var body: some View {
        HStack(spacing: 8) {
            Label("账户余额", systemImage: "creditcard")
                .font(.subheadline.weight(.medium))
            Spacer()
            if balance.granted > 0 {
                Text("含赠送 \(balance.symbol)\(balance.granted, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(balance.symbol)\(balance.total, specifier: "%.2f")")
                .font(.headline.monospacedDigit())
                .foregroundStyle(balance.total > 0 ? Color.primary : Color.red)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - 复制密钥行（Face ID 验证后复制，44pt 触控目标）

struct CopyKeyRow: View {
    let label: String
    let key: String

    @State private var copied = false
    @State private var authenticating = false

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 脱敏显示：前 3 位 + 11 个小号实心圆点 + 后 3 位
    private var maskedKey: String {
        let mask = String(repeating: "•", count: 11)
        guard trimmedKey.count > 6 else { return trimmedKey.isEmpty ? "未设置" : mask }
        return "\(trimmedKey.prefix(3))\(mask)\(trimmedKey.suffix(3))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(label, systemImage: "key")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(maskedKey)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button {
                copy()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        (copied ? Color.green : Color.accentColor).opacity(0.1),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedKey.isEmpty || authenticating)
            .accessibilityLabel(copied ? "已复制" : "复制\(label)")
        }
    }

    private func copy() {
        guard !trimmedKey.isEmpty, !authenticating else { return }
        authenticating = true
        Task { @MainActor in
            let unlocked = await BiometricGate.unlock(reason: "复制\(label)")
            authenticating = false
            guard unlocked else { return }
            UIPasteboard.general.string = trimmedKey
            withAnimation { copied = true }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}

// MARK: - 工具

/// 重置时间紧凑文案：今日 HH:mm / 明日 / M月d日
private func resetCaption(_ date: Date) -> String {
    let calendar = Calendar.current
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(date) {
        return "\(time) 重置"
    } else if calendar.isDateInTomorrow(date) {
        return "明日 \(time) 重置"
    }
    return "\(date.formatted(.dateTime.month(.defaultDigits).day())) \(time) 重置"
}
