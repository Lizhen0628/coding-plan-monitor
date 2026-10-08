import SwiftUI

// MARK: - 自定义侧边栏

struct AccountSidebar: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @Binding var selection: UUID?
    @State private var draggedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(vm.accounts) { account in
                        SidebarRow(
                            account: account,
                            selected: selection == account.id,
                            dragging: draggedID == account.id
                        )
                        .onTapGesture { selection = account.id }
                        .onDrag {
                            draggedID = account.id
                            selection = account.id
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
                .padding(8)
            }

            if vm.accounts.isEmpty {
                Text("点击下方 + 添加账号")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack(spacing: 6) {
                Menu {
                    ForEach(Provider.allCases, id: \.self) { provider in
                        Button(provider.displayName) {
                            selection = vm.addAccount(provider: provider)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("添加账号")

                Button(role: .destructive) {
                    if let selection,
                       let account = vm.accounts.first(where: { $0.id == selection }) {
                        vm.removeAccount(account)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.callout)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("删除选中账号")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

// MARK: - 账号行

private struct SidebarRow: View {
    @EnvironmentObject private var vm: MonitorViewModel
    let account: Account
    let selected: Bool
    let dragging: Bool

    @State private var hovering = false

    /// Key 脱敏显示：前 3 位 + *** + 后 3 位
    private var maskedKey: String {
        let key = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "未设置 Key" }
        guard key.count > 6 else { return "***" }
        return "\(key.prefix(3))***\(key.suffix(3))"
    }

    var body: some View {
        HStack(spacing: 8) {
            ProviderBadge(provider: account.provider, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.displayName(for: account))
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .primary)
                    .lineLimit(1)
                Text(maskedKey)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if !account.isVisible {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor)
            } else if hovering && !dragging {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .opacity(dragging ? 0.4 : 1)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}
