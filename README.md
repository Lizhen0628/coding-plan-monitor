# GLMMonitor

macOS 菜单栏原生应用（Swift / SwiftUI），监控 GLM Coding Plan 额度。

## 功能

- 菜单栏实时显示 5 小时窗口已用百分比
- 点击图标弹出面板：
  - **5 小时额度**：百分比 + 进度条 + 重置时间（点击可切换倒计时）
  - **每周额度**：同上
  - **MCP 每月**：已用 / 总次数 + 剩余次数
  - 上次刷新时间、在线状态
  - 手动刷新（⌘R）、设置（⌘,）、退出（⌘Q）
- 自动刷新（默认 5 分钟，可在设置中调整）
- 支持国内（bigmodel.cn）和国际（z.ai）平台

## 数据来源

官方订阅管理页同款接口（API Key 鉴权）：

```
GET https://open.bigmodel.cn/api/monitor/usage/quota/limit
Authorization: Bearer <API_KEY>
```

API Key 在 [智谱开放平台](https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys) 获取。

## 构建与运行

需要 macOS 14+ 和 Swift 工具链（Xcode 或 Command Line Tools）。

```bash
./build-app.sh     # 构建 GLMMonitor.app
open GLMMonitor.app
```

首次打开后，点击菜单栏图标 → 设置…，填入 API Key 即可。
