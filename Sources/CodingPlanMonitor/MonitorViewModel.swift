import Foundation
import SwiftUI

enum Provider: String, CaseIterable {
    case glm
    case kimi

    var displayName: String {
        switch self {
        case .glm: return "GLM Coding"
        case .kimi: return "Kimi Coding"
        }
    }

    /// 菜单栏紧凑前缀
    var shortLabel: String {
        switch self {
        case .glm: return "G"
        case .kimi: return "K"
        }
    }
}

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var usages: [Provider: ProviderUsage] = [:]
    @Published private(set) var errors: [Provider: String] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isLoading = false
    /// 处于倒计时显示模式的行（key 为「供应商-窗口」，点击切换），未包含的行显示重置时间点
    @Published var countdownRows: Set<String> = []

    @AppStorage("glmAPIKey") var glmAPIKey = ""
    @AppStorage("kimiAPIKey") var kimiAPIKey = ""
    /// "bigmodel"（国内）或 "zai"（国际）
    @AppStorage("glmPlatform") var glmPlatform = "bigmodel"
    @AppStorage("refreshMinutes") var refreshMinutes = 5

    var glmBaseURL: String {
        glmPlatform == "zai" ? "https://api.z.ai" : "https://open.bigmodel.cn"
    }

    func apiKey(for provider: Provider) -> String {
        switch provider {
        case .glm: return glmAPIKey
        case .kimi: return kimiAPIKey
        }
    }

    /// 已配置 Key 的供应商
    var configuredProviders: [Provider] {
        Provider.allCases.filter {
            !$0.apiKeyIsEmpty(self)
        }
    }

    var isOnline: Bool {
        lastRefresh != nil && errors.isEmpty
    }

    /// 菜单栏显示文本：各供应商 5 小时窗口已用百分比
    var menuBarTitle: String {
        let providers = configuredProviders
        guard !providers.isEmpty else { return "--" }
        let parts = providers.compactMap { provider -> String? in
            guard let p = usages[provider]?.fiveHour?.percentage else { return nil }
            let value = providers.count > 1 ? "\(provider.shortLabel):\(Int(p))%" : "\(Int(p))%"
            return value
        }
        return parts.isEmpty ? "--" : parts.joined(separator: " ")
    }

    // MARK: - 刷新

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let glmResult: Result<ProviderUsage, Error>? = fetchIfConfigured(.glm)
        async let kimiResult: Result<ProviderUsage, Error>? = fetchIfConfigured(.kimi)

        for (provider, result) in [(.glm, await glmResult), (.kimi, await kimiResult)] as [(Provider, Result<ProviderUsage, Error>?)] {
            guard let result else {
                // 未配置 Key：清空旧数据与错误
                usages[provider] = nil
                errors[provider] = nil
                continue
            }
            switch result {
            case .success(let usage):
                usages[provider] = usage
                errors[provider] = nil
            case .failure(let error):
                usages[provider] = nil
                errors[provider] = message(for: error)
            }
        }
        lastRefresh = Date()
    }

    private func fetchIfConfigured(_ provider: Provider) async -> Result<ProviderUsage, Error>? {
        let key = apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        do {
            switch provider {
            case .glm:
                return .success(try await GLMService.fetch(apiKey: key, baseURL: glmBaseURL))
            case .kimi:
                return .success(try await KimiService.fetch(apiKey: key))
            }
        } catch {
            return .failure(error)
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

private extension Provider {
    @MainActor
    func apiKeyIsEmpty(_ vm: MonitorViewModel) -> Bool {
        vm.apiKey(for: self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
