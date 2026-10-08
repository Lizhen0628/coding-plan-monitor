import WidgetKit
import SwiftUI

// MARK: - Widget Bundle

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodingPlanUsageWidget()
        QuotaLiveActivityWidget()
    }
}

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let accounts: [AccountUsageSnapshot]
    let updatedAt: Date?

    static let placeholder = UsageEntry(
        date: .now,
        accounts: [
            AccountUsageSnapshot(
                accountID: UUID(), displayName: "GLM 国内", shortLabel: "G", tintHex: "#5856D6",
                level: "pro",
                windows: [
                    QuotaWindowSnapshot(label: "5小时", percentage: 36, resetDate: .now.addingTimeInterval(5160)),
                    QuotaWindowSnapshot(label: "每周", percentage: 12, resetDate: .now.addingTimeInterval(3 * 86400)),
                ],
                balanceText: nil, hasError: false, updatedAt: .now
            ),
            AccountUsageSnapshot(
                accountID: UUID(), displayName: "Claude Code", shortLabel: "C", tintHex: "#FF9500",
                level: "max",
                windows: [QuotaWindowSnapshot(label: "5小时", percentage: 87, resetDate: .now.addingTimeInterval(3300))],
                balanceText: nil, hasError: false, updatedAt: .now
            ),
            AccountUsageSnapshot(
                accountID: UUID(), displayName: "DeepSeek", shortLabel: "D", tintHex: "#FF2D55",
                level: nil, windows: [],
                balanceText: "¥86.42", hasError: false, updatedAt: .now
            ),
        ],
        updatedAt: .now
    )
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = loadEntry()
        // 主 App 每次刷新都会 reloadAllTimelines；这里兜底 15 分钟
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> UsageEntry {
        let file = UsageSnapshotStore.load()
        return UsageEntry(date: .now, accounts: file?.accounts ?? [], updatedAt: file?.updatedAt)
    }
}

// MARK: - Widget

struct CodingPlanUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.lizhen.CodingPlanMonitoriOS.UsageWidget",
            provider: UsageTimelineProvider()
        ) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("额度用量")
        .description("最紧配额与重置倒计时，一目了然。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Views

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    /// 当前最紧的账号（按关键窗口百分比排序）
    private var rankedAccounts: [AccountUsageSnapshot] {
        entry.accounts.sorted {
            ($0.criticalWindow?.percentage ?? -1) > ($1.criticalWindow?.percentage ?? -1)
        }
    }

    var body: some View {
        if entry.accounts.isEmpty {
            emptyBody
        } else {
            switch family {
            case .systemMedium: mediumBody
            default: smallBody
            }
        }
    }

    // MARK: 小号：最紧配额圆环 + 倒计时

    @ViewBuilder
    private var smallBody: some View {
        if let account = rankedAccounts.first {
            if let window = account.criticalWindow {
                let tint = Self.statusColor(window.percentage, base: Color(hex: account.tintHex))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        badge(account, size: 24)
                        Text(account.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(alignment: .center) {
                        ring(percentage: window.percentage, tint: tint)
                            .frame(width: 52, height: 52)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(window.label)额度")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let reset = window.resetDate, reset > .now {
                                Text(timerInterval: .now...reset, countsDown: true)
                                    .font(.caption.monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                                Text("后重置")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("已重置")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                // 纯余额账号（如 DeepSeek）
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        badge(account, size: 24)
                        Text(account.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("账户余额")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(account.balanceText ?? "--")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color(hex: account.tintHex))
                }
            }
        }
    }

    // MARK: 中号：Top 3 账号行

    private var mediumBody: some View {
        VStack(spacing: 10) {
            ForEach(rankedAccounts.prefix(3)) { account in
                row(account)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if let updatedAt = entry.updatedAt {
                    Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func row(_ account: AccountUsageSnapshot) -> some View {
        HStack(spacing: 10) {
            badge(account, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let window = account.criticalWindow {
                    let tint = Self.statusColor(window.percentage, base: Color(hex: account.tintHex))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(tint.opacity(0.15))
                            Capsule().fill(tint)
                                .frame(width: max(4, geo.size.width * window.percentage / 100))
                        }
                    }
                    .frame(height: 5)
                } else {
                    Text("账户余额")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if account.hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let window = account.criticalWindow {
                let tint = Self.statusColor(window.percentage, base: Color(hex: account.tintHex))
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(window.percentage))%")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                    if let reset = window.resetDate, reset > .now {
                        Text(timerInterval: .now...reset, countsDown: true)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(account.balanceText ?? "--")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color(hex: account.tintHex))
            }
        }
    }

    // MARK: 空态

    private var emptyBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("打开 Plan Monitor\n添加账号后这里显示用量")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 组件

    private func badge(_ account: AccountUsageSnapshot, size: CGFloat) -> some View {
        Text(account.shortLabel)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: account.tintHex).gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }

    private func ring(percentage: Double, tint: Color) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(percentage, 100) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percentage))")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    /// 阈值配色：≥80 红 / ≥50 橙 / 其余用供应商品牌色
    private static func statusColor(_ percentage: Double, base: Color) -> Color {
        if percentage >= 80 { return .red }
        if percentage >= 50 { return .orange }
        return base
    }
}

// MARK: - 工具

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension AccountUsageSnapshot: Identifiable {
    var id: UUID { accountID }
}

#Preview("小号", as: .systemSmall) {
    CodingPlanUsageWidget()
} timeline: {
    UsageEntry.placeholder
}

#Preview("中号", as: .systemMedium) {
    CodingPlanUsageWidget()
} timeline: {
    UsageEntry.placeholder
}
