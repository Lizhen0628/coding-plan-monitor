import SwiftUI

/// 供应商徽标（用量卡片、账号列表、编辑页共用）
struct ProviderBadge: View {
    let provider: Provider
    var size: CGFloat = 26

    var body: some View {
        Text(provider.shortLabel)
            .font(.system(size: size * 0.42, weight: .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(provider.tint.gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
