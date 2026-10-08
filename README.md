# Coding Plan Monitor（GLMMonitor）

多平台 Coding Plan 用量监控：**macOS 菜单栏**、**iPhone**（含主屏小组件与 Live Activity）与 **Windows 托盘**，共享同一套数据接口与解析逻辑，支持 10 家供应商。

- GLM（智谱）、Kimi、火山引擎、通义（阿里云百炼）、Claude Code、OpenAI Codex、MiniMax、GitHub Copilot、Gemini CLI、DeepSeek
- 同一供应商可配置多个订阅；GLM 支持国内（bigmodel.cn）/ 国际（z.ai），通义与 MiniMax 支持国内 / 国际区域

## macOS 版

菜单栏原生应用（Swift / SwiftUI，macOS 14+）。

- 菜单栏实时显示各账号 5 小时窗口已用百分比
- 点击图标弹出面板：**5 小时额度** / **每周额度**（百分比 + 进度条 + 重置时间，点击切换倒计时）、**每月总额度**、**MCP 每月**、账户余额
- 支持从本机自动导入 Claude Code / Codex CLI / Gemini CLI 凭证
- 手动刷新（⌘R）、自动刷新（默认 5 分钟，可调）、设置（⌘,）

```bash
./build-app.sh     # 构建 Coding Plan Monitor.app（ad-hoc 签名）
open "Coding Plan Monitor.app"
```

## iOS 版

iPhone 原生应用（Swift / SwiftUI，iOS 17+），双 Tab（用量 / 账号）+ 下拉刷新。

- **用量页**：账号卡片 + 展开详情（各配额窗口进度条、重置倒计时、趋势曲线、脱敏凭证复制）
- **主屏幕小组件**：小号 = 最紧配额圆环 + 重置倒计时；中号 = Top 3 账号用量条
- **Live Activity**：配额 ≥90% 时锁屏与灵动岛常驻倒计时，回落或重置后自动结束
- **额度提醒**：用量超 80% / 95% 推送告警，额度重置完成通知，余额跌破阈值（¥10 / $2）预警，每周一 09:00 周用量报告
- **后台刷新**：`BGAppRefreshTask` 静默拉取，通知在 App 未打开时也能触发
- **凭证安全**：凭证存 Keychain（iCloud Keychain 同步），复制前需 Face ID / 密码验证；账号配置走 iCloud KVS 多设备同步
- **用量分享卡片**：一键生成 PNG 报告卡分享

iOS 沙盒无法读取 `~/.claude`、`~/.codex` 等本机文件，Token 类凭证需在电脑上复制后传到手机粘贴。真机运行需在 Apple Developer 后台为 App ID 开启 **App Groups**（`group.com.lizhen.CodingPlanMonitor`）与 **iCloud** 能力，Automatic Signing 通常会自动处理。

## Windows 版

功能等价的 C# / WPF 系统托盘应用位于 [`windows/`](windows/README.md)，使用相同的数据接口与解析逻辑。安装 .NET 8 SDK 后：

```powershell
cd windows
.\build-app.ps1   # 输出 artifacts\CodingPlanMonitor.exe（单文件自包含）
```

## 数据来源

各端使用完全一致的接口（均为各平台官方控制台同款接口，凭证仅存储在本机 / 本机 Keychain）：

| 供应商 | 接口 | 凭证 |
|---|---|---|
| GLM | `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`（国际 `https://api.z.ai`） | API Key（[获取](https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys)） |
| Kimi | `GET https://api.kimi.com/coding/v1/usages` | `sk-kimi-` API Key（[获取](https://www.kimi.com/code/console)） |
| Claude | `GET https://api.anthropic.com/api/oauth/usage` | Claude Code OAuth Token |
| Codex | `GET https://chatgpt.com/backend-api/wham/usage` | Access Token + Account ID |
| 通义 | 百炼控制台 `queryCodingPlanInstanceInfoV2` | `sk-sp-` API Key |
| 火山引擎 | `GetCodingPlanUsage`（V4 签名） | AK / SK |
| MiniMax | `GET {host}/v1/api/openplatform/coding_plan/remains` | API Key |
| Copilot | `GET https://api.github.com/copilot_internal/user` | GitHub OAuth Token |
| Gemini | Code Assist `retrieveUserQuota` | OAuth Refresh Token |
| DeepSeek | `GET https://api.deepseek.com/user/balance` | API Key |

## 工程结构与构建

需要 Xcode 16+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```
├─ CodingPlanMonitor.xcworkspace     # 打开这个
├─ Apple/
│  ├─ project.yml                    # XcodeGen 工程定义（三 target）
│  ├─ CodingPlanMonitor.xcodeproj    # 由 project.yml 生成
│  ├─ Shared/                        # macOS / iOS 共享
│  │  ├─ Models.swift                # 供应商、账号、归一化用量模型
│  │  └─ Services/                   # 10 家供应商配额服务（纯 Foundation/CryptoKit）
│  ├─ iOS/
│  │  ├─ Sources/CodingPlanMonitor/  # App：入口、ViewModel、Views、iOS 专属服务
│  │  ├─ Sources/Shared/             # App 与小组件共享（App Group / 快照 / Live Activity 属性）
│  │  ├─ Sources/UsageWidget/        # 小组件 + Live Activity 扩展
│  │  ├─ Configuration/ Entitlements/ Assets.xcassets/ Design/
│  └─ macOS/
│     ├─ Sources/                    # 入口、ViewModel、本机凭证导入、Views
│     └─ Assets.xcassets / PrivacyInfo / entitlements
├─ windows/                          # C# / WPF 移植版
├─ scripts/                          # 图标 / 截图 / App Store Connect 工具
├─ images/ marketing/ APPSTORE.md    # 商店与发布材料
└─ build-app.sh                      # macOS 快速构建
```

```bash
(cd Apple && xcodegen generate)      # 生成/更新 Xcode 工程
open CodingPlanMonitor.xcworkspace   # Xcode 中选 CodingPlanMonitor-macOS / -iOS scheme 运行

# 命令行验证构建
xcodebuild -project Apple/CodingPlanMonitor.xcodeproj -scheme CodingPlanMonitor-macOS \
  -destination 'platform=macOS' build
xcodebuild -project Apple/CodingPlanMonitor.xcodeproj -scheme CodingPlanMonitor-iOS \
  -destination 'generic/platform=iOS Simulator' build
```

首次使用：macOS 点击菜单栏图标 → 设置… 填入 API Key；iOS 进入「账号」Tab → 右上角 + 添加账号粘贴凭证。
