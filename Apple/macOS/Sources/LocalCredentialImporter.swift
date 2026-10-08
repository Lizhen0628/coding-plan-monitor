import Foundation

/// 从本机已登录的 Claude Code / Codex CLI 凭据中导入 Token。
/// 沙盒或凭据不存在时返回 nil，调用方引导用户手动粘贴。
enum LocalCredentialImporter {

    /// Claude Code OAuth Token（sk-ant-oat-…）
    /// 依次尝试：~/.claude/.credentials.json → macOS 钥匙串 "Claude Code-credentials"
    static func claudeOAuthToken(includeKeychain: Bool = true) -> String? {
        // Linux/Windows 路径（部分 macOS 版本也写文件）
        let filePath = NSHomeDirectory() + "/.claude/.credentials.json"
        if let token = claudeToken(fromJSONFile: filePath) {
            return token
        }
        // macOS 钥匙串（可能触发系统授权弹窗，后台自动刷新时不使用）
        guard includeKeychain else { return nil }
        for service in ["Claude Code-credentials", "Claude Code"] {
            if let raw = keychainGenericPassword(service: service) {
                if raw.hasPrefix("sk-ant"), raw.contains("-oat") {
                    return raw
                }
                if let data = raw.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let oauth = object["claudeAiOauth"] as? [String: Any],
                   let token = oauth["accessToken"] as? String, !token.isEmpty {
                    return token
                }
            }
        }
        return nil
    }

    /// Codex CLI 凭证：~/.codex/auth.json → (accessToken, accountId)
    static func codexCredentials() -> (accessToken: String, accountId: String)? {
        var paths = [NSHomeDirectory() + "/.codex/auth.json"]
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            paths.insert(codexHome + "/auth.json", at: 0)
        }
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = object["tokens"] as? [String: Any] else { continue }
            let accessToken = (tokens["access_token"] as? String) ?? (tokens["accessToken"] as? String)
            guard let accessToken, !accessToken.isEmpty else { continue }
            let accountId = (tokens["account_id"] as? String) ?? (tokens["accountId"] as? String) ?? ""
            return (accessToken, accountId)
        }
        return nil
    }

    // MARK: - 私有

    /// GitHub Copilot OAuth Token（gho_…）：~/.config/github-copilot/hosts.json
    static func copilotOAuthToken() -> String? {
        var paths = [NSHomeDirectory() + "/.config/github-copilot/hosts.json"]
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            paths.insert(xdg + "/github-copilot/hosts.json", at: 0)
        }
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // 结构：{"github.com": {"oauth_token": "gho_..."}}
            for value in object.values {
                guard let entry = value as? [String: Any],
                      let token = entry["oauth_token"] as? String, !token.isEmpty else { continue }
                return token
            }
        }
        return nil
    }

    /// Gemini CLI OAuth Refresh Token：~/.gemini/oauth_creds.json
    static func geminiRefreshToken() -> String? {
        let path = NSHomeDirectory() + "/.gemini/oauth_creds.json"
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["refresh_token"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private static func claudeToken(fromJSONFile path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// 读取钥匙串 generic password（可能触发系统授权弹窗，仅在用户主动点击时调用）
    private static func keychainGenericPassword(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
