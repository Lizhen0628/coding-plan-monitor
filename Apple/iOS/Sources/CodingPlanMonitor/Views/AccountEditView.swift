import SwiftUI
import UIKit

/// 新建与编辑共用：existing 为 nil 时新建
struct AccountEditView: View {
    @EnvironmentObject private var vm: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    let existing: Account?

    @State private var provider: Provider = .glm
    @State private var name = ""
    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var glmPlatform = "bigmodel"
    @State private var region = "cn"
    @State private var isVisible = true
    @State private var showDeleteConfirm = false

    /// 凭证输入框焦点（用于框内脱敏：失焦显示 前3***后3，聚焦显示完整值）
    private enum CredentialField: Hashable { case apiKey, secretKey }
    @FocusState private var focusedCredential: CredentialField?

    init(existing: Account?) {
        self.existing = existing
        if let account = existing {
            _provider = State(initialValue: account.provider)
            _name = State(initialValue: account.name)
            _apiKey = State(initialValue: account.apiKey)
            _secretKey = State(initialValue: account.secretKey)
            _glmPlatform = State(initialValue: account.glmPlatform)
            _region = State(initialValue: account.region)
            _isVisible = State(initialValue: account.isVisible)
        }
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSecret: String {
        secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 凭证是否填写完整
    private var isCredentialComplete: Bool {
        switch provider.credentialKind {
        case .akSK:
            return !trimmedKey.isEmpty && !trimmedSecret.isEmpty
        default:
            return !trimmedKey.isEmpty
        }
    }

    private var hasChanges: Bool {
        guard let account = existing else { return true }
        return account.name != name
            || account.apiKey != apiKey
            || account.secretKey != secretKey
            || account.glmPlatform != glmPlatform
            || account.region != region
            || account.isVisible != isVisible
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("供应商") {
                        providerPicker
                    }
                } else {
                    Section("供应商") {
                        HStack(spacing: 10) {
                            ProviderBadge(provider: provider, size: 30)
                            Text(provider.displayName)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("账号信息") {
                    TextField("备注名", text: $name, prompt: Text("可选，如「\(provider.nameExample)」"))
                }

                Section("监控") {
                    Toggle("显示用量", isOn: $isVisible)
                    Text("关闭后该订阅不在用量页显示，也不再自动刷新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                credentialSection

                if provider == .glm {
                    Section("平台") {
                        Picker("平台", selection: $glmPlatform) {
                            Text("国内（bigmodel.cn）").tag("bigmodel")
                            Text("国际（z.ai）").tag("zai")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if let regionOptions = provider.regionOptions {
                    Section("区域") {
                        Picker("区域", selection: $region) {
                            ForEach(regionOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        if let caption = provider.regionCaption {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("删除该账号", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加账号" : "编辑账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isCredentialComplete || !hasChanges)
                }
            }
            .confirmationDialog(
                "确定删除「\(name.isEmpty ? provider.displayName : name)」吗？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除账号", role: .destructive) {
                    if let account = existing {
                        vm.removeAccount(account)
                    }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 供应商选择（新建时横向卡片）

    private var providerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Provider.allCases, id: \.rawValue) { candidate in
                    let isSelected = candidate == provider
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { provider = candidate }
                    } label: {
                        VStack(spacing: 5) {
                            ProviderBadge(provider: candidate, size: 32)
                            Text(candidate.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 凭证区（按供应商形态）

    @ViewBuilder
    private var credentialSection: some View {
        switch provider.credentialKind {
        case .apiKey:
            Section {
                secureFieldRow("API Key", text: $apiKey, placeholder: provider.keyPlaceholder, tag: .apiKey)
                helpLinkRow
            } header: {
                Text("凭证")
            } footer: {
                Text("在 \(provider.displayName) 控制台获取凭证后粘贴到上方")
            }

        case .akSK:
            Section {
                secureFieldRow("AccessKey ID", text: $apiKey, placeholder: "AKLT…", tag: .apiKey)
                secureFieldRow("Secret Access Key", text: $secretKey, placeholder: "从 IAM 控制台获取", tag: .secretKey)
                helpLinkRow
            } header: {
                Text("访问凭证（AK/SK）")
            } footer: {
                Text("在 \(provider.displayName) IAM 控制台创建 AK/SK 对后粘贴到上方")
            }

        case .claudeOAuth:
            Section {
                secureFieldRow("OAuth Token", text: $apiKey, placeholder: provider.keyPlaceholder, tag: .apiKey)
            } header: {
                Text("OAuth Token")
            } footer: {
                Text("在电脑上登录 Claude Code 后，从 ~/.claude/.credentials.json 复制 OAuth Token 粘贴到上方")
            }

        case .codexOAuth:
            Section {
                secureFieldRow("Access Token", text: $apiKey, placeholder: provider.keyPlaceholder, tag: .apiKey)
                secureFieldRow("Account ID", text: $secretKey, placeholder: "可选，多账号时必填", tag: .secretKey)
            } header: {
                Text("Codex 凭证")
            } footer: {
                Text("在电脑上登录 Codex CLI 后，从 ~/.codex/auth.json 复制 access_token 与 account_id 粘贴到上方")
            }

        case .geminiOAuth:
            Section {
                secureFieldRow("Refresh Token", text: $apiKey, placeholder: provider.keyPlaceholder, tag: .apiKey)
            } header: {
                Text("OAuth 凭证")
            } footer: {
                Text("在电脑上登录 Gemini CLI 后，从 ~/.gemini/oauth_creds.json 复制 refresh_token 粘贴到上方")
            }
        }
    }

    /// 凭证输入行：输入框内直接脱敏 + 粘贴/清空按钮
    private func secureFieldRow(_ label: String, text: Binding<String>, placeholder: String, tag: CredentialField) -> some View {
        HStack(spacing: 8) {
            TextField(label, text: maskedBinding(text, tag: tag), prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedCredential, equals: tag)
                .onSubmit { focusedCredential = nil }
            if text.wrappedValue.isEmpty {
                Button("粘贴") {
                    if let string = UIPasteboard.general.string {
                        text.wrappedValue = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            } else {
                Button {
                    text.wrappedValue = ""
                    focusedCredential = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空\(label)")
            }
        }
        .padding(.vertical, 2)
    }

    /// 框内脱敏：未聚焦时显示 开头3位***结尾3位，聚焦编辑时显示完整值
    private func maskedBinding(_ binding: Binding<String>, tag: CredentialField) -> Binding<String> {
        Binding(
            get: {
                let value = binding.wrappedValue
                guard focusedCredential != tag else { return value }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return value }
                guard trimmed.count > 6 else { return String(repeating: "•", count: 11) }
                return "\(trimmed.prefix(3))\(String(repeating: "•", count: 11))\(trimmed.suffix(3))"
            },
            set: { binding.wrappedValue = $0 }
        )
    }

    @ViewBuilder
    private var helpLinkRow: some View {
        Link(destination: provider.keyHelpURL) {
            Label("打开控制台获取凭证", systemImage: "arrow.up.right.square")
                .font(.subheadline)
        }
    }

    // MARK: - 保存

    private func save() {
        guard isCredentialComplete else { return }
        var account = existing ?? Account(provider: provider)
        account.name = name.trimmingCharacters(in: .whitespaces)
        account.apiKey = trimmedKey
        account.secretKey = trimmedSecret
        account.glmPlatform = glmPlatform
        account.region = region
        account.isVisible = isVisible

        if existing != nil {
            vm.updateAccount(account)
        } else {
            vm.addAccount(account)
        }
        // 保存后立即拉取一次，让用量页尽快有数据
        Task { await vm.refresh() }
        dismiss()
    }
}
