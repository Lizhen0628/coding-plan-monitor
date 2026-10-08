import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @AppStorage(NotificationManager.enabledDefaultsKey) private var alertsEnabled = true
    @AppStorage(LiveActivityManager.thresholdDefaultsKey) private var liveActivityThreshold = 90.0
    @State private var editingAccount: Account?
    @State private var addingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vm.accounts) { account in
                        Button {
                            editingAccount = account
                        } label: {
                            row(for: account)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onMove(perform: vm.moveAccounts)
                    .onDelete(perform: vm.deleteAccounts)
                } header: {
                    Text("账号")
                } footer: {
                    Text("同一供应商可添加多个订阅。凭证保存在本机，仅用于向对应平台查询用量。")
                }

                Section {
                    Picker("自动刷新间隔", selection: Binding(
                        get: { vm.refreshMinutes },
                        set: { vm.setRefreshMinutes($0) }
                    )) {
                        ForEach([1, 2, 3, 5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                } header: {
                    Text("刷新")
                } footer: {
                    Text("用量页打开、回到前台和下拉时都会立即刷新。")
                }

                Section {
                    Toggle("额度提醒", isOn: $alertsEnabled)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("灵动岛提醒阈值")
                            Spacer()
                            Text(liveActivityThreshold >= 100 ? "关闭" : "\(Int(liveActivityThreshold))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $liveActivityThreshold, in: 50...100, step: 1) { editing in
                            if !editing {
                                vm.resyncLiveActivities()
                            }
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("用量超过 80% / 95%、以及额度重置完成时推送通知；超过灵动岛阈值时锁屏与灵动岛常驻倒计时（100% 即关闭）。提醒依赖后台刷新，实际频率由系统调度。")
                }
            }
            .navigationTitle("账号")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加账号")
                }
            }
            .sheet(isPresented: $addingNew) {
                AccountEditView(existing: nil)
                    .environmentObject(vm)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditView(existing: account)
                    .environmentObject(vm)
                    .interactiveDismissDisabled()
            }
        }
    }

    // MARK: - 账号行

    private func row(for account: Account) -> some View {
        HStack(spacing: 10) {
            ProviderBadge(provider: account.provider, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.displayName(for: account))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(account.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if account.isConfigured {
                if !account.isVisible {
                    Text("已隐藏")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("待填写凭证")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
