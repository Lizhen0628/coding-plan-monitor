import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class MonitorViewModel: ObservableObject {
    /// 供后台刷新任务访问当前实例
    static weak var current: MonitorViewModel?
    /// key 为账号 ID
    @Published private(set) var usages: [UUID: ProviderUsage] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isLoading = false
    /// 处于倒计时显示模式的行（key 为「账号ID-窗口」，点击切换），未包含的行显示重置时间点
    @Published var countdownRows: Set<String> = []
    /// 账号列表 JSON（变更时持久化到 UserDefaults）
    @Published private(set) var accountsData: Data {
        didSet { UserDefaults.standard.set(accountsData, forKey: "accountsData") }
    }
    /// 自动刷新间隔（分钟）
    @Published private(set) var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes") }
    }

    private let cloudSync = CloudSyncManager()

    init() {
        accountsData = UserDefaults.standard.data(forKey: "accountsData") ?? Data()
        let stored = UserDefaults.standard.integer(forKey: "refreshMinutes")
        refreshMinutes = stored > 0 ? stored : 5
        Self.current = self

        migrateCredentialsToKeychainIfNeeded()

        cloudSync.onExternalChange = { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.accountsData = data
                await self.refresh()
            }
        }
        cloudSync.start()
    }

    /// 自动刷新间隔（1~60 分钟）
    func setRefreshMinutes(_ minutes: Int) {
        refreshMinutes = min(max(1, minutes), 60)
        BackgroundRefreshManager.schedule()
    }

    // MARK: - 账号存取

    /// 账号列表（凭证从 Keychain 回填）
    var accounts: [Account] {
        get {
            var list = (try? JSONDecoder().decode([Account].self, from: accountsData)) ?? []
            for index in list.indices {
                let keys = KeychainStore.credentialKeys(for: list[index].id)
                if let apiKey = KeychainStore.get(keys.apiKey) { list[index].apiKey = apiKey }
                if let secretKey = KeychainStore.get(keys.secretKey) { list[index].secretKey = secretKey }
            }
            return list
        }
    }

    private func setAccounts(_ newValue: [Account]) {
        persistCredentials(for: newValue)
        // UserDefaults / iCloud KVS 只存脱敏后的配置，凭证只进 Keychain
        let stripped = newValue.map { account in
            var copy = account
            copy.apiKey = ""
            copy.secretKey = ""
            return copy
        }
        accountsData = (try? JSONEncoder().encode(stripped)) ?? Data()

        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: CloudSyncManager.localTimestampDefaultsKey)
        cloudSync.push(accountsData, updatedAt: now)

        writeWidgetSnapshot()
    }

    /// 凭证写入 Keychain（空值等价删除）
    private func persistCredentials(for accounts: [Account]) {
        for account in accounts {
            let keys = KeychainStore.credentialKeys(for: account.id)
            KeychainStore.set(account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: keys.apiKey)
            KeychainStore.set(account.secretKey.trimmingCharacters(in: .whitespacesAndNewlines), for: keys.secretKey)
        }
    }

    /// 旧版本凭证明文存在 UserDefaults JSON 里，首次启动迁移到 Keychain
    private func migrateCredentialsToKeychainIfNeeded() {
        guard let raw = try? JSONDecoder().decode([Account].self, from: accountsData) else { return }
        guard raw.contains(where: { !$0.apiKey.isEmpty || !$0.secretKey.isEmpty }) else { return }
        setAccounts(raw)
    }

    @discardableResult
    func addAccount(_ account: Account) -> UUID {
        var list = accounts
        list.append(account)
        setAccounts(list)
        return account.id
    }

    func updateAccount(_ account: Account) {
        var list = accounts
        if let index = list.firstIndex(where: { $0.id == account.id }) {
            list[index] = account
            setAccounts(list)
        }
    }

    /// List onMove 拖动排序
    func moveAccounts(fromOffsets: IndexSet, toOffset: Int) {
        var list = accounts
        list.move(fromOffsets: fromOffsets, toOffset: toOffset)
        setAccounts(list)
    }

    func removeAccount(_ account: Account) {
        setAccounts(accounts.filter { $0.id != account.id })
        usages[account.id] = nil
        errors[account.id] = nil
        deleteCredentials(for: account.id)
    }

    func deleteAccounts(at offsets: IndexSet) {
        let removed = offsets.map { accounts[$0] }
        var list = accounts
        list.remove(atOffsets: offsets)
        setAccounts(list)
        for account in removed {
            usages[account.id] = nil
            errors[account.id] = nil
            deleteCredentials(for: account.id)
        }
    }

    private func deleteCredentials(for accountID: UUID) {
        let keys = KeychainStore.credentialKeys(for: accountID)
        KeychainStore.delete(keys.apiKey)
        KeychainStore.delete(keys.secretKey)
        HistoryStore.remove(accountID: accountID)
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

    /// 显示名：优先用户备注名；同供应商多账号时自动编号
    func displayName(for account: Account) -> String {
        let name = account.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let siblings = configuredAccounts.filter { $0.provider == account.provider }
        if siblings.count > 1, let index = siblings.firstIndex(where: { $0.id == account.id }) {
            return "\(account.provider.displayName) \(index + 1)"
        }
        return account.provider.displayName
    }

    // MARK: - 刷新

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let targets = monitoredAccounts
        let validIDs = Set(targets.map(\.id))

        // 清理已删除/隐藏账号的缓存
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
                usages[id] = nil
                errors[id] = message(for: error)
            }
        }
        lastRefresh = Date()

        recordHistory()
        writeWidgetSnapshot()
        NotificationManager.evaluate(accounts: monitoredAccounts, usages: usages, displayName: displayName(for:))
        LiveActivityManager.sync(accounts: monitoredAccounts, usages: usages, displayName: displayName(for:))
    }

    // MARK: - 用量历史

    /// 每次刷新为各窗口记录一个历史点（供趋势 sparkline）
    private func recordHistory() {
        for account in monitoredAccounts {
            guard let usage = usages[account.id] else { continue }
            if let window = usage.fiveHour {
                HistoryStore.record(accountID: account.id, label: "5小时", percentage: window.percentage)
            }
            if let window = usage.weekly {
                HistoryStore.record(accountID: account.id, label: "每周", percentage: window.percentage)
            }
            if let window = usage.monthly {
                HistoryStore.record(accountID: account.id, label: "每月", percentage: window.percentage)
            }
            for extra in usage.extras {
                HistoryStore.record(accountID: account.id, label: extra.label, percentage: extra.percentage)
            }
            if let mcp = usage.mcp, mcp.total > 0 {
                HistoryStore.record(accountID: account.id, label: "MCP", percentage: Double(mcp.used) / Double(mcp.total) * 100)
            }
        }
        HistoryStore.persist()
    }

    /// 阈值设置变更后立即重同步 Live Activity（无需等下次刷新）
    func resyncLiveActivities() {
        LiveActivityManager.sync(accounts: monitoredAccounts, usages: usages, displayName: displayName(for:))
    }

    // MARK: - 小组件快照

    /// 把最新用量写入 App Group 容器并触发 Widget 刷新
    private func writeWidgetSnapshot() {
        let snapshots = monitoredAccounts.map { account -> AccountUsageSnapshot in
            let usage = usages[account.id]
            var windows: [QuotaWindowSnapshot] = []
            if let window = usage?.fiveHour {
                windows.append(.init(label: "5小时", percentage: window.percentage, resetDate: window.resetDate))
            }
            if let window = usage?.weekly {
                windows.append(.init(label: "每周", percentage: window.percentage, resetDate: window.resetDate))
            }
            if let window = usage?.monthly {
                windows.append(.init(label: "每月", percentage: window.percentage, resetDate: window.resetDate))
            }
            for extra in usage?.extras ?? [] {
                windows.append(.init(label: extra.label, percentage: extra.percentage, resetDate: extra.resetDate))
            }
            var balanceText: String?
            if let balance = usage?.balance {
                balanceText = "\(balance.symbol)\(String(format: "%.2f", balance.total))"
            }
            return AccountUsageSnapshot(
                accountID: account.id,
                displayName: displayName(for: account),
                shortLabel: account.provider.shortLabel,
                tintHex: account.provider.tintHex,
                level: usage?.level,
                windows: windows,
                balanceText: balanceText,
                hasError: errors[account.id] != nil,
                updatedAt: Date()
            )
        }
        UsageSnapshotStore.save(UsageSnapshotFile(updatedAt: Date(), accounts: snapshots))
        WidgetCenter.shared.reloadAllTimelines()
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
