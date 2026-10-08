import SwiftUI

// MARK: - 设计 Token 与共用组件（对齐 Design/preview.html）

/// 全屏统一的状态配色：<50 绿 / 50–80 橙 / ≥80 红，强调色只留给品牌与 CTA
enum StatusColor {
    static func forPercentage(_ percentage: Double?) -> Color {
        guard let percentage else { return .secondary }
        if percentage >= 80 { return .red }
        if percentage >= 50 { return .orange }
        return .green
    }
}

/// 配额圆环：收起态卡片的唯一主角数字
struct QuotaRing: View {
    let percentage: Double
    let tint: Color
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(percentage, 0), 100) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percentage))")
                .font(.system(size: size * 0.27, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// 状态 chip：次级配额降级为一行摘要
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(tint.opacity(0.1), in: Capsule())
    }
}
