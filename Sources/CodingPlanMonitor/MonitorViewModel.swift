import Foundation
import SwiftUI

@MainActor
final class MonitorViewModel: ObservableObject {
    /// key 为账号 ID
    @Published private(set) var usages: [UUID: ProviderUsage] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isLoading = false
    /// 处于倒计时显示模式的行（key 为「账号ID-窗口」，点击切换），未包含的行显示重置时间点
    @Published var countdownRows: Set<String> = []

    /// 账号列表（JSON 编码存储）
    @AppStorage("accountsData") var accountsData = Data()
    @AppStorage("refreshMinutes") var refreshMinutes = 5
    /// 是否在菜单栏显示用量百分比（关闭后只显示图标）
    @AppStorage("showMenuBarUsage") var showMenuBarUsage = false

    // 旧版单 Key 存储（仅用于首次迁移）
    @AppStorage("glmAPIKey") private var legacyGLMKey = ""
    @AppStorage("kimiAPIKey") private var legacyKimiKey = ""
    @AppStorage("glmPlatform") private var legacyGLMPlatform = "bigmodel"

    init() {
        migrateLegacyKeys()
    }

    // MARK: - 账号存取

    var accounts: [Account] {
        get { (try? JSONDecoder().decode([Account].self, from: accountsData)) ?? [] }
        set { accountsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    @discardableResult
    func addAccount(provider: Provider) -> UUID {
        let account = Account(provider: provider)
        var list = accounts
        list.append(account)
        accounts = list
        return account.id
    }

    /// 列表 onMove 拖动排序
    func moveAccounts(fromOffsets: IndexSet, toOffset: Int) {
        var list = accounts
        list.move(fromOffsets: fromOffsets, toOffset: toOffset)
        accounts = list
    }

    func removeAccount(_ account: Account) {
        accounts = accounts.filter { $0.id != account.id }
        usages[account.id] = nil
        errors[account.id] = nil
    }

    /// 拖动排序：把 draggedID 移动到 targetID 的位置（向下拖动时落在其后）
    func moveAccount(draggedID: UUID, over targetID: UUID) {
        var list = accounts
        guard let from = list.firstIndex(where: { $0.id == draggedID }),
              let originalTo = list.firstIndex(where: { $0.id == targetID }),
              from != originalTo else { return }
        let item = list.remove(at: from)
        let to = list.firstIndex(where: { $0.id == targetID })!
        list.insert(item, at: from < originalTo ? to + 1 : to)
        accounts = list
    }

    /// 供设置界面使用的账号绑定（每次写入都会持久化到 AppStorage）
    func binding(for id: UUID) -> Binding<Account> {
        Binding(
            get: { self.accounts.first { $0.id == id } ?? Account(provider: .glm) },
            set: { newValue in
                var list = self.accounts
                if let index = list.firstIndex(where: { $0.id == id }) {
                    list[index] = newValue
                    self.accounts = list
                }
            }
        )
    }

    /// 旧版单 Key 配置迁移为账号列表（迁移后清空旧字段，避免重复迁移）
    private func migrateLegacyKeys() {
        guard accounts.isEmpty else { return }
        var migrated: [Account] = []
        let glmKey = legacyGLMKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !glmKey.isEmpty {
            migrated.append(Account(provider: .glm, apiKey: glmKey, glmPlatform: legacyGLMPlatform))
        }
        let kimiKey = legacyKimiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kimiKey.isEmpty {
            migrated.append(Account(provider: .kimi, apiKey: kimiKey))
        }
        guard !migrated.isEmpty else { return }
        accounts = migrated
        legacyGLMKey = ""
        legacyKimiKey = ""
    }

    // MARK: - 派生状态

    /// 已配置凭证的账号
    var configuredAccounts: [Account] {
        accounts.filter(\.isConfigured)
    }

    /// 实际参与监控与展示的账号（已配置 Key 且未被隐藏）
    var monitoredAccounts: [Account] {
        configuredAccounts.filter(\.isVisible)
    }

    var isOnline: Bool {
        lastRefresh != nil && errors.isEmpty
    }

    /// 面板显示名：优先用户备注名；同供应商多账号时自动编号
    func displayName(for account: Account) -> String {
        let name = account.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let siblings = configuredAccounts.filter { $0.provider == account.provider }
        if siblings.count > 1, let index = siblings.firstIndex(where: { $0.id == account.id }) {
            return "\(account.provider.displayName) \(index + 1)"
        }
        return account.provider.displayName
    }

    /// 菜单栏紧凑标签：备注名（取前 4 字）或供应商前缀 + 编号
    func shortLabel(for account: Account) -> String {
        let name = account.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return String(name.prefix(4)) }
        let siblings = configuredAccounts.filter { $0.provider == account.provider }
        if siblings.count > 1, let index = siblings.firstIndex(where: { $0.id == account.id }) {
            return "\(account.provider.shortLabel)\(index + 1)"
        }
        return account.provider.shortLabel
    }

    /// 菜单栏显示文本：各账号 5 小时窗口已用百分比
    var menuBarTitle: String {
        let accounts = monitoredAccounts
        guard !accounts.isEmpty else { return "--" }
        let parts = accounts.compactMap { account -> String? in
            guard let p = usages[account.id]?.fiveHour?.percentage else { return nil }
            if accounts.count > 1 {
                return "\(shortLabel(for: account)):\(Int(p))%"
            }
            return "\(Int(p))%"
        }
        return parts.isEmpty ? "--" : parts.joined(separator: " ")
    }

    // MARK: - 刷新

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let targets = monitoredAccounts
        let validIDs = Set(targets.map(\.id))

        // 清理已删除账号的缓存
        usages = usages.filter { validIDs.contains($0.key) }
        errors = errors.filter { validIDs.contains($0.key) }

        let results = await withTaskGroup(
            of: (UUID, Result<ProviderUsage, Error>).self,
            returning: [UUID: Result<ProviderUsage, Error>].self
        ) { group in
            for account in targets {
                group.addTask {
                    let result: Result<ProviderUsage, Error>
                    do {
                        result = .success(try await Self.fetch(account))
                    } catch {
                        result = .failure(error)
                    }
                    return (account.id, result)
                }
            }
            var collected: [UUID: Result<ProviderUsage, Error>] = [:]
            for await (id, result) in group {
                collected[id] = result
            }
            return collected
        }

        for (id, result) in results {
            switch result {
            case .success(let usage):
                usages[id] = usage
                errors[id] = nil
            case .failure(let error):
                // Token 类供应商（Claude/Codex）：凭证过期时自动从本机重新导入并重试一次
                if let account = targets.first(where: { $0.id == id }),
                   let refreshed = Self.reimportCredentials(for: account) {
                    do {
                        let usage = try await Self.fetch(refreshed)
                        persist(refreshed)
                        usages[id] = usage
                        errors[id] = nil
                        continue
                    } catch let retryError {
                        usages[id] = nil
                        errors[id] = message(for: retryError)
                        continue
                    }
                }
                usages[id] = nil
                errors[id] = message(for: error)
            }
        }
        lastRefresh = Date()
    }

    /// Claude/Codex 凭证自动续期：仅读取本地文件（不触发钥匙串弹窗）
    private nonisolated static func reimportCredentials(for account: Account) -> Account? {
        switch account.provider {
        case .claude:
            guard let token = LocalCredentialImporter.claudeOAuthToken(includeKeychain: false),
                  token != account.apiKey else { return nil }
            var updated = account
            updated.apiKey = token
            return updated
        case .openai:
            guard let credentials = LocalCredentialImporter.codexCredentials(),
                  credentials.accessToken != account.apiKey else { return nil }
            var updated = account
            updated.apiKey = credentials.accessToken
            if !credentials.accountId.isEmpty {
                updated.secretKey = credentials.accountId
            }
            return updated
        case .gemini:
            guard let token = LocalCredentialImporter.geminiRefreshToken(),
                  token != account.apiKey else { return nil }
            var updated = account
            updated.apiKey = token
            return updated
        default:
            return nil
        }
    }

    private func persist(_ account: Account) {
        var list = accounts
        if let index = list.firstIndex(where: { $0.id == account.id }) {
            list[index] = account
            accounts = list
        }
    }

    private nonisolated static func fetch(_ account: Account) async throws -> ProviderUsage {
        let key = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch account.provider {
        case .glm:
            let baseURL = account.glmPlatform == "zai" ? "https://api.z.ai" : "https://open.bigmodel.cn"
            return try await GLMService.fetch(apiKey: key, baseURL: baseURL)
        case .kimi:
            return try await KimiService.fetch(apiKey: key)
        case .volcengine:
            return try await VolcengineService.fetch(accessKey: key, secretKey: account.secretKey)
        case .alibaba:
            return try await AlibabaService.fetch(apiKey: key, region: account.region)
        case .claude:
            return try await ClaudeService.fetch(oauthToken: key)
        case .openai:
            return try await OpenAIService.fetch(accessToken: key, accountId: account.secretKey)
        case .minimax:
            return try await MiniMaxService.fetch(apiKey: key, region: account.region)
        case .copilot:
            return try await CopilotService.fetch(oauthToken: key)
        case .gemini:
            return try await GeminiService.fetch(refreshToken: key)
        case .deepseek:
            return try await DeepSeekService.fetch(apiKey: key)
        }
    }

    private func message(for error: Error) -> String {
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet
            || urlError.code == .timedOut
            || urlError.code == .networkConnectionLost {
            return "网络连接异常"
        }
        return error.localizedDescription
    }

    // MARK: - 文案

    /// 切换某一行的重置时间显示模式（时间点 ↔ 倒计时），按行独立
    func toggleCountdown(_ key: String) {
        if countdownRows.contains(key) {
            countdownRows.remove(key)
        } else {
            countdownRows.insert(key)
        }
    }

    private func isCountdown(_ key: String) -> Bool {
        countdownRows.contains(key)
    }

    /// 5 小时窗口副标题：默认显示重置时间点，点击切换为倒计时
    func fiveHourSubtitle(_ window: QuotaWindow?, key: String) -> String {
        guard let date = window?.resetDate else { return "" }
        if isCountdown(key) { return countdownText(to: date) }
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) {
            return "今日 \(time) 重置"
        } else if calendar.isDateInTomorrow(date) {
            return "明日 \(time) 重置"
        }
        return "\(date.formatted(.dateTime.month(.defaultDigits).day())) \(time) 重置"
    }

    /// 每周窗口副标题：默认显示倒计时，点击切换为重置时间点
    func weeklySubtitle(_ window: QuotaWindow?, key: String) -> String {
        guard let date = window?.resetDate else { return "" }
        if isCountdown(key) {
            let time = date.formatted(date: .abbreviated, time: .shortened)
            return "\(time) 重置"
        }
        return countdownText(to: date)
    }

    private func countdownText(to date: Date) -> String {
        let interval = max(0, Int(date.timeIntervalSinceNow))
        let days = interval / 86400
        let hours = (interval % 86400) / 3600
        let minutes = (interval % 3600) / 60
        if days > 0 {
            return "\(days) 天 \(hours) 小时后重置"
        } else if hours > 0 {
            return "\(hours) 小时 \(minutes) 分后重置"
        }
        return "\(minutes) 分后重置"
    }
}
