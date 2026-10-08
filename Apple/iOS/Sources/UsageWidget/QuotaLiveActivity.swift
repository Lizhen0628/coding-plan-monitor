import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity（配额告急：锁屏卡 + 灵动岛）

struct QuotaLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QuotaActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
        } dynamicIsland: { context in
            let tint = Color(hex: context.state.tintHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ActivityBadge(shortLabel: context.state.shortLabel, tint: tint, size: 24)
                        Text(context.state.accountName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.percentage))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.state.windowLabel)额度告急")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let reset = context.state.resetDate, reset > .now {
                            HStack(spacing: 4) {
                                Text(timerInterval: .now...reset, countsDown: true)
                                    .font(.caption.monospacedDigit())
                                Text("后重置")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } compactLeading: {
                Text("\(Int(context.state.percentage))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.red)
            } compactTrailing: {
                if let reset = context.state.resetDate, reset > .now {
                    Text(timerInterval: .now...reset, countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                }
            } minimal: {
                Text("\(Int(context.state.percentage))")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - 锁屏卡片

private struct LockScreenActivityView: View {
    let state: QuotaActivityAttributes.ContentState

    private var tint: Color { Color(hex: state.tintHex) }

    var body: some View {
        HStack(spacing: 12) {
            ActivityBadge(shortLabel: state.shortLabel, tint: tint, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.accountName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(state.windowLabel)额度告急")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(state.percentage))%")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.red)
                if let reset = state.resetDate, reset > .now {
                    HStack(spacing: 2) {
                        Text(timerInterval: .now...reset, countsDown: true)
                            .font(.caption2.monospacedDigit())
                        Text("后重置")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - 徽标

private struct ActivityBadge: View {
    let shortLabel: String
    let tint: Color
    var size: CGFloat

    var body: some View {
        Text(shortLabel)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
