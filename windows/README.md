# Coding Plan Monitor — Windows 版

macOS 菜单栏应用 [Coding Plan Monitor](../README.md) 的 Windows 移植版：C# / WPF（.NET 8）系统托盘应用，
与 macOS 版使用完全相同的接口与解析逻辑，监控 10 家供应商的 Coding Plan 额度：

GLM Coding · Kimi Coding · 火山引擎 Coding · 通义 Coding · Claude Code · OpenAI Codex ·
MiniMax Coding · GitHub Copilot · Gemini CLI · DeepSeek

## 功能

- 系统托盘图标实时显示第一个账号 5 小时窗口已用百分比（图标数字 + 颜色阈值；可在设置中关闭，悬停 tooltip 显示全部账号）
- 左键点击托盘图标弹出面板（点击外部自动收起），按账号分区显示：
  - **5 小时额度**：百分比 + 进度条 + 重置时间（点击可切换倒计时）
  - **每周额度**：同上
  - **每月总额度**（Kimi / 火山 / Copilot 等）
  - **MCP 每月**（GLM）：已用 / 总次数 + 剩余次数
  - **Pro / Flash 每日配额**（Gemini）、**账户余额**（DeepSeek）
  - 上次刷新时间、在线状态
  - 手动刷新（Ctrl+R）、设置（Ctrl+,）、退出（Ctrl+Q）
- 自动刷新（默认 5 分钟，可在设置中调整 1~60 分钟）
- 右键托盘图标：打开面板 / 刷新 / 设置 / 退出
- 同一供应商可添加多个订阅账号；Claude / Codex / Gemini 凭证过期时自动从本机重新导入并重试

## 构建与运行

需要 **Windows 10/11** 和 **.NET 8 SDK**（[下载](https://dotnet.microsoft.com/download)）。

```powershell
# 方式一：脚本（单文件自包含 EXE，输出到 windows\artifacts\）
.\build-app.ps1

# 方式二：dotnet CLI
cd CodingPlanMonitor
dotnet build -c Release
dotnet run            # 开发调试
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o ..\artifacts
```

首次运行后，左键点击系统托盘图标 → 设置…，添加账号并填入对应供应商的凭证即可（可只配一个，也可多个都配）。

## 数据来源

与 macOS 版完全一致（详见各 `Services/*.cs` 文件头注释）：

| 供应商 | 接口 | 凭证 |
| --- | --- | --- |
| GLM | `GET open.bigmodel.cn / api.z.ai /api/monitor/usage/quota/limit` | API Key |
| Kimi | `GET api.kimi.com/coding/v1/usages` | `sk-kimi-` API Key |
| 火山引擎 | `POST open.volcengineapi.com`（V4 HMAC-SHA256 签名，service: ark） | AK/SK |
| 通义 | `POST bailian.console.aliyun.com/data/api.json` | `sk-sp-` API Key |
| Claude | `GET api.anthropic.com/api/oauth/usage` | OAuth Token（`sk-ant-oat-`） |
| OpenAI Codex | `GET chatgpt.com/backend-api/wham/usage` | Access Token + Account ID |
| MiniMax | `GET {host}/v1/api/openplatform/coding_plan/remains` | API Key |
| Copilot | `GET api.github.com/copilot_internal/user` | `gho_` OAuth Token |
| Gemini | OAuth 刷新 + `cloudcode-pa.googleapis.com` | Refresh Token |
| DeepSeek | `GET api.deepseek.com/user/balance` | API Key |

本机凭证自动导入路径（Windows）：

- Claude Code：`%USERPROFILE%\.claude\.credentials.json`
- Codex CLI：`%USERPROFILE%\.codex\auth.json`（或 `%CODEX_HOME%\auth.json`）
- GitHub Copilot：`%USERPROFILE%\.config\github-copilot\hosts.json`
- Gemini CLI：`%USERPROFILE%\.gemini\oauth_creds.json`

## 与 macOS 版的差异

- 菜单栏文本 → 托盘图标数字 + 悬停 tooltip（Windows 托盘不支持纯文本）
- UserDefaults → `%APPDATA%\CodingPlanMonitor\settings.json`（JSON 结构与 macOS 版账号字段一致）
- Claude 钥匙串导入 → 仅文件导入（Claude Code 在 Windows 上本来就走文件）
- 界面为浅色主题，暂未跟随系统深色模式
