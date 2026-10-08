using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace CodingPlanMonitor;

/// <summary>
/// 从本机已登录的 Claude Code / Codex CLI / Copilot / Gemini CLI 凭据中导入 Token。
/// Windows 版仅读取本地文件（macOS 版的钥匙串读取不适用于 Windows；
/// Claude Code 在 Windows 上本来就写 ~/.claude/.credentials.json 文件）。
/// 凭据不存在时返回 null，调用方引导用户手动粘贴。
/// </summary>
internal static class LocalCredentialImporter
{
    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// <summary>Claude Code OAuth Token（sk-ant-oat-…）：~/.claude/.credentials.json</summary>
    public static string? ClaudeOAuthToken() =>
        ClaudeTokenFromFile(Path.Combine(Home, ".claude", ".credentials.json"));

    /// <summary>Codex CLI 凭证：~/.codex/auth.json → (accessToken, accountId)</summary>
    public static (string AccessToken, string AccountId)? CodexCredentials()
    {
        var paths = new List<string> { Path.Combine(Home, ".codex", "auth.json") };
        var codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
        if (!string.IsNullOrEmpty(codexHome))
            paths.Insert(0, Path.Combine(codexHome, "auth.json"));

        foreach (var path in paths)
        {
            try
            {
                if (!File.Exists(path)) continue;
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                if (!doc.RootElement.TryGetProperty("tokens", out var tokens) ||
                    tokens.ValueKind != JsonValueKind.Object) continue;

                var accessToken = GetString(tokens, "access_token") ?? GetString(tokens, "accessToken");
                if (string.IsNullOrEmpty(accessToken)) continue;
                var accountId = GetString(tokens, "account_id") ?? GetString(tokens, "accountId") ?? "";
                return (accessToken, accountId);
            }
            catch
            {
                // 尝试下一个路径
            }
        }
        return null;
    }

    /// <summary>GitHub Copilot OAuth Token（gho_…）：~/.config/github-copilot/hosts.json</summary>
    public static string? CopilotOAuthToken()
    {
        var paths = new List<string> { Path.Combine(Home, ".config", "github-copilot", "hosts.json") };
        var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        if (!string.IsNullOrEmpty(xdg))
            paths.Insert(0, Path.Combine(xdg, "github-copilot", "hosts.json"));
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (!string.IsNullOrEmpty(localAppData))
            paths.Add(Path.Combine(localAppData, "github-copilot", "hosts.json"));

        foreach (var path in paths)
        {
            try
            {
                if (!File.Exists(path)) continue;
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                // 结构：{"github.com": {"oauth_token": "gho_..."}}
                foreach (var entry in doc.RootElement.EnumerateObject())
                {
                    if (entry.Value.ValueKind != JsonValueKind.Object) continue;
                    var token = GetString(entry.Value, "oauth_token");
                    if (!string.IsNullOrEmpty(token)) return token;
                }
            }
            catch
            {
                // 尝试下一个路径
            }
        }
        return null;
    }

    /// <summary>Gemini CLI OAuth Refresh Token：~/.gemini/oauth_creds.json</summary>
    public static string? GeminiRefreshToken()
    {
        try
        {
            var path = Path.Combine(Home, ".gemini", "oauth_creds.json");
            if (!File.Exists(path)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            return GetString(doc.RootElement, "refresh_token");
        }
        catch
        {
            return null;
        }
    }

    private static string? ClaudeTokenFromFile(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (!doc.RootElement.TryGetProperty("claudeAiOauth", out var oauth) ||
                oauth.ValueKind != JsonValueKind.Object) return null;
            return GetString(oauth, "accessToken");
        }
        catch
        {
            return null;
        }
    }

    private static string? GetString(JsonElement obj, string key) =>
        obj.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String &&
        v.GetString() is { Length: > 0 } s
            ? s
            : null;
}
