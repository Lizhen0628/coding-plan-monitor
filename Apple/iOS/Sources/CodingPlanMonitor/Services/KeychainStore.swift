import Foundation
import Security

/// 凭证安全存储：API Key / OAuth Token / AK-SK 全部进 Keychain。
/// kSecAttrSynchronizable = true → 通过 iCloud Keychain 在登录同一 Apple ID 的设备间同步，
/// 因此 iCloud 同步账号配置（KVS）时无需也不会传输凭证明文。
enum KeychainStore {
    private static let service = "com.lizhen.CodingPlanMonitor.credentials"

    static func credentialKeys(for accountID: UUID) -> (apiKey: String, secretKey: String) {
        ("\(accountID.uuidString).apiKey", "\(accountID.uuidString).secretKey")
    }

    /// 写入凭证；空字符串等价于删除
    static func set(_ value: String, for key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = baseQuery(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// 读取凭证；不存在返回 nil
    static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    /// SynchronizableAny：同时命中本机与 iCloud Keychain 中的条目
    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}
