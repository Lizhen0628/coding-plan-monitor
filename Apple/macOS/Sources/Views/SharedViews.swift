import SwiftUI

/// 供应商徽标（面板与设置页共用）
struct ProviderBadge: View {
    let provider: Provider
    var size: CGFloat = 26

    var body: some View {
        Text(provider.shortLabel)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(provider.tint.gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

// MARK: - 账号拖动排序代理（面板与设置侧边栏共用）

@MainActor
struct AccountDropDelegate: DropDelegate {
    let target: Account
    let vm: MonitorViewModel
    @Binding var draggedID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != target.id else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            vm.moveAccount(draggedID: draggedID, over: target.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}
