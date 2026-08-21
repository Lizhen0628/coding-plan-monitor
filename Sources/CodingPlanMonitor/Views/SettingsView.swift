import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @State private var selection: UUID?
    @State private var importMessage: String?

    var body: some View {
        TabView {
            accountsTab
                .tabItem { Label("账号", systemImage: "key") }
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 400)
    }

    // MARK: - 账号页（自定义侧边栏 + 详情）

    private var accountsTab: some View {
        HStack(spacing: 0) {
            AccountSidebar(selection: $selection)
                .frame(width: 200)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: vm.accountsData) {
            ensureSelection()
            Task { await vm.refresh() }
        }
    }

    // MARK: - 详情编辑

    @ViewBuilder
    private var detailView: some View {
        if let selection, let account = vm.accounts.first(where: { $0.id == selection }) {
            let binding = vm.binding(for: selection)
            Form {
                Section("账号信息") {
                    LabeledContent("供应商", value: account.provider.displayName)
                    TextField("备注名", text: binding.name, prompt: Text("可选，如「\(account.provider.nameExample)」"))
                }

                Section("监控") {
                    Toggle("在监控面板显示用量", isOn: binding.isVisible)
                    Text("关闭后该订阅不在监控面板与菜单栏中显示，也不再自动刷新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                credentialSection(account: account, binding: binding)

                if account.provider == .glm {
                    Section("平台") {
                        Picker("平台", selection: binding.glmPlatform) {
                            Text("国内（bigmodel.cn）").tag("bigmodel")
                            Text("国际（z.ai）").tag("zai")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if let regionOptions = account.provider.regionOptions {
                    Section("区域") {
                        Picker("区域", selection: binding.region) {
                            ForEach(regionOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        if let caption = account.provider.regionCaption {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("删除该账号", role: .destructive, action: removeSelected)
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "key")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("选择左侧账号进行编辑")
                    .foregroundStyle(.secondary)
                Text("或点击左下角 + 添加")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 凭证区（按供应商形态）

    @ViewBuilder
    private func credentialSection(account: Account, binding: Binding<Account>) -> some View {
        switch account.provider.credentialKind {
        case .apiKey:
            Section("API Key") {
                SecureField("API Key", text: binding.apiKey, prompt: Text(account.provider.keyPlaceholder))
                if account.provider == .copilot {
                    HStack {
                        Button("从本机 GitHub Copilot 导入") {
                            if let token = LocalCredentialImporter.copilotOAuthToken() {
                                binding.wrappedValue.apiKey = token
                                importMessage = "✓ 已导入"
                            } else {
                                importMessage = "未找到本机凭据，请手动粘贴"
                            }
                            clearImportMessageLater()
                        }
                        if let importMessage {
                            Text(importMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("需先在本机登录 GitHub Copilot；Token 也可从 ~/.config/github-copilot/hosts.json 手动获取")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Link(account.provider == .copilot ? "查看用量与订阅 →" : "获取 API Key →", destination: account.provider.keyHelpURL)
                    .font(.caption)
            }

        case .akSK:
            Section("访问凭证（AK/SK）") {
                SecureField("AccessKey ID", text: binding.apiKey, prompt: Text("AKLT…"))
                SecureField("Secret Access Key", text: binding.secretKey, prompt: Text("从 IAM 控制台获取"))
                Link("获取 AK/SK →", destination: account.provider.keyHelpURL)
                    .font(.caption)
            }

        case .claudeOAuth:
            Section("OAuth Token") {
                SecureField("OAuth Token", text: binding.apiKey, prompt: Text(account.provider.keyPlaceholder))
                HStack {
                    Button("从本机 Claude Code 导入") {
                        importClaudeToken(into: binding)
                    }
                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("需先在本机登录 Claude Code；Token 也可从 ~/.claude/.credentials.json 手动获取")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .codexOAuth:
            Section("Codex 凭证") {
                SecureField("Access Token", text: binding.apiKey, prompt: Text(account.provider.keyPlaceholder))
                SecureField("Account ID", text: binding.secretKey, prompt: Text("可选，多账号时必填"))
                HStack {
                    Button("从本机 Codex CLI 导入") {
                        importCodexCredentials(into: binding)
                    }
                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("需先在本机登录 Codex CLI；凭证也可从 ~/.codex/auth.json 手动获取")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .geminiOAuth:
            Section("OAuth 凭证") {
                SecureField("Refresh Token", text: binding.apiKey, prompt: Text(account.provider.keyPlaceholder))
                HStack {
                    Button("从本机 Gemini CLI 导入") {
                        if let token = LocalCredentialImporter.geminiRefreshToken() {
                            binding.wrappedValue.apiKey = token
                            importMessage = "✓ 已导入"
                        } else {
                            importMessage = "未找到 ~/.gemini/oauth_creds.json，请手动粘贴"
                        }
                        clearImportMessageLater()
                    }
                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("需先在本机登录 Gemini CLI（gemini 命令）；凭证位于 ~/.gemini/oauth_creds.json")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importClaudeToken(into binding: Binding<Account>) {
        if let token = LocalCredentialImporter.claudeOAuthToken() {
            binding.wrappedValue.apiKey = token
            importMessage = "✓ 已导入"
        } else {
            importMessage = "未找到本机凭据，请手动粘贴"
        }
        clearImportMessageLater()
    }

    private func importCodexCredentials(into binding: Binding<Account>) {
        if let credentials = LocalCredentialImporter.codexCredentials() {
            binding.wrappedValue.apiKey = credentials.accessToken
            if !credentials.accountId.isEmpty {
                binding.wrappedValue.secretKey = credentials.accountId
            }
            importMessage = "✓ 已导入"
        } else {
            importMessage = "未找到 ~/.codex/auth.json，请手动粘贴"
        }
        clearImportMessageLater()
    }

    private func clearImportMessageLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            importMessage = nil
        }
    }

    // MARK: - 通用页

    private var generalTab: some View {
        Form {
            Section("菜单栏") {
                Toggle("显示用量百分比", isOn: $vm.showMenuBarUsage)
                Text("关闭后菜单栏仅显示图标，用量信息仍可在面板中查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("刷新") {
                Stepper("自动刷新间隔：\(vm.refreshMinutes) 分钟", value: $vm.refreshMinutes, in: 1...60)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - 操作

    private func removeSelected() {
        guard let selection,
              let account = vm.accounts.first(where: { $0.id == selection }) else { return }
        vm.removeAccount(account)
        self.selection = vm.accounts.first?.id
    }

    private func ensureSelection() {
        let ids = vm.accounts.map(\.id)
        if selection == nil || !ids.contains(selection!) {
            selection = ids.first
        }
    }
}
