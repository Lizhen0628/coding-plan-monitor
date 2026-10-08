using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodingPlanMonitor;

/// <summary>
/// 设置持久化：%APPDATA%\CodingPlanMonitor\settings.json
/// （macOS 版使用 UserDefaults，Windows 版使用 JSON 文件）
/// </summary>
public sealed class SettingsStore
{
    public List<Account> Accounts { get; set; } = new();
    public int RefreshMinutes { get; set; } = 5;
    /// <summary>是否在托盘图标上显示用量百分比（关闭后只显示仪表盘图标）</summary>
    public bool ShowMenuBarUsage { get; set; }

    private static string DirPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CodingPlanMonitor");

    private static string FilePath => Path.Combine(DirPath, "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
    };

    public static SettingsStore Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var dto = JsonSerializer.Deserialize<Dto>(File.ReadAllText(FilePath), JsonOptions);
                if (dto != null)
                {
                    return new SettingsStore
                    {
                        Accounts = dto.Accounts ?? new List<Account>(),
                        RefreshMinutes = dto.RefreshMinutes is >= 1 and <= 60 ? dto.RefreshMinutes.Value : 5,
                        ShowMenuBarUsage = dto.ShowMenuBarUsage,
                    };
                }
            }
        }
        catch
        {
            // 配置文件损坏时回退默认值
        }
        return new SettingsStore();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(DirPath);
            var dto = new Dto
            {
                Accounts = Accounts,
                RefreshMinutes = RefreshMinutes,
                ShowMenuBarUsage = ShowMenuBarUsage,
            };
            File.WriteAllText(FilePath, JsonSerializer.Serialize(dto, JsonOptions));
        }
        catch
        {
            // 写入失败不阻塞使用
        }
    }

    private sealed class Dto
    {
        [JsonPropertyName("accounts")] public List<Account>? Accounts { get; set; }
        [JsonPropertyName("refreshMinutes")] public int? RefreshMinutes { get; set; }
        [JsonPropertyName("showMenuBarUsage")] public bool ShowMenuBarUsage { get; set; }
    }
}
