# Coding Plan Monitor（GLMMonitor）

macOS 菜单栏原生应用（Swift / SwiftUI），监控 GLM Coding Plan 与 Kimi Coding Plan 额度。

## 功能

- 菜单栏实时显示各供应商 5 小时窗口已用百分比（同时配置多个时带 `G:` / `K:` 前缀）
- 点击图标弹出面板，按供应商分区显示：
  - **5 小时额度**：百分比 + 进度条 + 重置时间（点击可切换倒计时）
  - **每周额度**：同上
  - **每月总额度**（Kimi）：百分比 + 进度条
  - **MCP 每月**（GLM）：已用 / 总次数 + 剩余次数
  - 上次刷新时间、在线状态
  - 手动刷新（⌘R）、设置（⌘,）、退出（⌘Q）
- 自动刷新（默认 5 分钟，可在设置中调整）
- GLM 支持国内（bigmodel.cn）和国际（z.ai）平台

## 数据来源

**GLM**：官方订阅管理页同款接口（API Key 鉴权）：

```
GET https://open.bigmodel.cn/api/monitor/usage/quota/limit
Authorization: Bearer <API_KEY>
```

API Key 在 [智谱开放平台](https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys) 获取。

**Kimi**：Kimi Code 用量接口（`sk-kimi-` API Key 鉴权，非开放平台按量 Key）：

```
GET https://api.kimi.com/coding/v1/usages
Authorization: Bearer <API_KEY>
```

API Key 在 [Kimi Code 控制台](https://www.kimi.com/code/console) 创建。该接口未公开文档，返回的数值字段为字符串格式。

## 构建与运行

需要 macOS 14+ 和 Swift 工具链（Xcode 或 Command Line Tools）。

```bash
./build-app.sh     # 构建 Coding Plan Monitor.app
open "Coding Plan Monitor.app"
```

首次打开后，点击菜单栏图标 → 设置…，填入对应供应商的 API Key 即可（可只填一个，也可两个都填）。
