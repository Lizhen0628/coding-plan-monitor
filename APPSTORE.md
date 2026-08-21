# App Store 上架指南

代码侧的准备工作已全部完成（Xcode 工程、沙盒、图标、隐私清单、签名配置、CLI Release/Archive 验证）。
以下步骤需要你本人在 Xcode 和 App Store Connect 中操作。

## 已完成（本地）

- `CodingPlanMonitor.xcodeproj`：由 `project.yml`（XcodeGen）生成，改配置后跑 `xcodegen generate` 即可
- Bundle ID：`com.lizhen.CodingPlanMonitor`（如要改，编辑 `project.yml` 后重新生成）
- App Sandbox + network.client 权限（`CodingPlanMonitor.entitlements`）
- 1024px 图标（`Assets.xcassets`，由 `scripts/make-icon.swift` 生成）
- 隐私清单（`PrivacyInfo.xcprivacy`，声明 UserDefaults 访问）
- 分类：Utilities；`LSUIElement`（无 Dock 图标）
- Release 构建 + Archive 签名配置验证通过（CLI 验证；Distribution 证书在首次 Archive 时由 Xcode 自动创建）

## 需要你操作的步骤

### 1. Xcode 账号与签名（约 5 分钟）

1. `open CodingPlanMonitor.xcodeproj`
2. Xcode → Settings → Accounts，登录你的 Apple ID，确认团队 `2CV6VKVD26`（App Store Connect 所在团队）在列
3. 选中 target → Signing & Capabilities，确认勾选 "Automatically manage signing"，Team 选择你的付费团队
4. 首次 Archive 时 Xcode 会提示创建 **Apple Distribution** 证书，点确认即可（目前钥匙串里只有 Development 证书）

### 2. App Store Connect 创建应用（约 10 分钟）

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)
2. **协议、税务和银行业务**：签署「付费 App 协议」并填写收款银行卡与税务信息（收费应用必须，否则无法定价）
3. 我的 App → 新建 App：
   - 平台：macOS
   - 名称：如「Coding Plan 监控」（商店显示名，30 字符内，需唯一）
   - Bundle ID：选 `com.lizhen.CodingPlanMonitor`
   - SKU：如 `coding-plan-monitor-mac`

### 3. 上传构建

任选一种：

- **Xcode GUI**：选 "Any Mac" 目标，Product → Archive，然后 Organizer → Distribute App → App Store Connect → Upload
- **命令行**（账号登录 Xcode 后）：

  ```bash
  xcodebuild -project CodingPlanMonitor.xcodeproj -scheme CodingPlanMonitor \
    -configuration Release -archivePath build/CodingPlanMonitor.xcarchive \
    archive -allowProvisioningUpdates

  xcodebuild -exportArchive -archivePath build/CodingPlanMonitor.xcarchive \
    -exportPath build/export -exportOptionsPlist build/ExportOptions.plist \
    -allowProvisioningUpdates   # destination=upload，直接上传到 App Store Connect
  ```

  或在 Xcode Organizer 中 Distribute App → App Store Connect → Upload。

上传后等几分钟处理完成，在 App Store Connect 的构建版本中选择它。

### 4. 商店信息（约 30 分钟）

- **价格**：App 信息 → 价格与销售范围，定价 **¥2**。前提：已签署「付费 App 协议」并填写收款银行卡与税务信息，否则价格不可选。**注意：苹果价格点没有 ¥0.99 这档，人民币区间为 ¥1～¥74,999**
- **截图**：至少一张 1280×800 或 1440×900 的 Mac 截图。运行应用、打开面板后按 `Cmd+Shift+4` 截面板（需含菜单栏弹出界面）
- **描述/关键词/宣传文本**：参考下方草稿
- **隐私政策 URL**：必填。应用不收集任何数据，写一个简单页面（GitHub Pages / Gitee Pages 均可）声明「不收集、不传输任何用户数据，API Key 仅存储在本机」
- **年龄分级**：填问卷，应为 4+
- **审核信息**（关键，最容易踩坑）：
  - 备注里说明：这是菜单栏工具，需要 GLM / Kimi Coding Plan 的 API Key 才能显示数据
  - **提供可用的测试 API Key** 给审核员（建议各平台新建一个专用 Key，审核通过后吊销）
  - 说明：点击菜单栏图标打开面板 → 设置 → 填入 Key

### 5. 提交审核

提交后通常 24~48 小时出结果。常见拒因及对策：

- 「打开后无内容」→ 审核备注里的测试 Key 和操作说明要写清楚
- 「菜单栏应用没有主窗口」→ 备注说明 LSUIElement 设计如此，参照同类工具

## 描述草稿

> Coding Plan Monitor 是一款 macOS 菜单栏工具，帮你随时查看 GLM / Kimi Coding Plan 的额度使用情况：
> • 5 小时与每周 Token 额度：百分比、进度条、重置倒计时
> • 每月总额度与 MCP 每月调用次数
> • 自动刷新，额度告急一目了然
> 需要 GLM 或 Kimi Coding Plan 订阅及 API Key 才能使用。

## 注意

- 上架后的版本使用沙盒，之前通过 `defaults write` 存的 Key 不通用，首次使用需在设置里重新填入
- GLM 与 Kimi 的额度接口均为订阅管理页同款接口，非公开文档接口；若服务商调整接口，需要发版跟进
- 本地免签名调试仍可继续用 `./build-app.sh`
