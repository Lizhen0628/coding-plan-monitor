import Foundation

/// iCloud KVS 同步账号配置（last-write-wins）。
/// 凭证不在此同步——它们存于 kSecAttrSynchronizable 的 Keychain 条目，走 iCloud Keychain。
@MainActor
final class CloudSyncManager {
    private static let dataKey = "cloud.accountsData"
    private static let timestampKey = "cloud.accountsUpdatedAt"
    static let localTimestampDefaultsKey = "accountsUpdatedAt"

    /// 云端数据更新且比本地新时回调（data 为不含凭证的账号 JSON）
    var onExternalChange: ((Data) -> Void)?

    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pullIfNewer() }
        }
        store.synchronize()
        pullIfNewer()
    }

    /// 本地账号变更后推送
    func push(_ data: Data, updatedAt: Date) {
        store.set(data, forKey: Self.dataKey)
        store.set(updatedAt.timeIntervalSince1970, forKey: Self.timestampKey)
        store.synchronize()
    }

    /// 云端比本地新则采用
    private func pullIfNewer() {
        guard let data = store.data(forKey: Self.dataKey) else { return }
        let cloudTimestamp = store.double(forKey: Self.timestampKey)
        let localTimestamp = UserDefaults.standard.double(forKey: Self.localTimestampDefaultsKey)
        guard cloudTimestamp > localTimestamp else { return }
        UserDefaults.standard.set(cloudTimestamp, forKey: Self.localTimestampDefaultsKey)
        onExternalChange?(data)
    }
}
