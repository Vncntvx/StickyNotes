# Research: macOS 27 原生质感重设计（Liquid Glass）

**Feature**: `003-macos27-liquid-glass-redesign` | **Date**: 2026-08-09 | **Input**: `spec.md` + 5 项 clarify 决策

---

## 1. 仓库与架构现状（Repository Map）

产品区域 → 现有实现 → 关键文件/类型 → 状态归属 → 持久化依赖 → 计划影响。

### 1.1 App 层（`App/Sources/`，45 文件，组合根）

| 产品区域 | 现有实现 | 关键文件/类型 | 计划影响 |
|---|---|---|---|
| 入口 | 4 个场景：`MenuBarExtra`(.window)、`Settings`、`Window("About…")`、`Window("Help…")` | `App/StickyNotesApp.swift`（AppDelegate + bootstrap + `wireGlobalShortcuts` + 窗口 fallback `openSettingsWindow` 等） | REFACTOR：加菜单/命令体系；移除对 footer 的依赖；`searchAll`/`toggleLibrary` 补全行为 |
| Library 窗口 | 系统 MenuBarExtra 窗口 + 定位探针 | `Features/Library/MenuBarLibraryScene.swift`、`MenuBarLibraryWindowProbe`、`MenuBarWindowFrame`（SystemBridge） | REFACTOR：窗口不变，内部改原生工具栏 |
| Library 结构 | header（新建 + Notes/Trash 分段）+ 自定义搜索行 + 卡片网格 + footer | `MenuBarLibraryScene`、`LibrarySearchView`、`LibraryCardGrid`、`SyncStatusView`、`LibraryModel` | REPLACE 结构：单一原生工具栏；移除 footer |
| 卡片网格 | `LazyVGrid`，固定 220×160/12pt/3-2-1 列 | `LibraryCardGrid.swift`、`NoteCardView.swift`、`CardProjection`（Persistence） | REFACTOR：FR-021 公式化自适应 + 密度 72–128 |
| 搜索 | 自定义 TextField（非 `.searchable`），无防抖 | `LibrarySearchView.swift`、`LibraryModel.setSearchQuery` → `SearchService` | REPLACE：原生工具栏搜索 |
| Trash | Library 内 scope；`TrashView.swift` 为死代码（含唯一 Empty Trash 确认对话框，不可达） | `TrashView.swift`、`LibraryModel.scope/emptyTrash` | REPLACE：Trash 目的地 UI + Empty Trash 确认（FR-026） |
| 同步状态 | footer 常驻 `SyncStatusView`（5 态 + Sync Now） | `SyncStatusView.swift` | REPLACE：注意态上下文横幅（FR-010），正常态零占位 |
| 笔记窗口 | 手动 `NSWindow` + `NSHostingView`，透明标题栏保留红绿灯 | `Features/NoteWindow/NoteWindowCoordinator.swift`、`NoteWindowHostModel.swift`、`NoteControlsView.swift`、`NoteWindowBridge`/`WindowLevelBridge`/`DisplayChangeBridge`（SystemBridge） | REFACTOR：内容定位/失活外观/浮动控件玻璃呈现；无窗口重写 |
| 编辑器 | `NSTextView`（NSViewRepresentable；TextEditor 绑定在 27 beta 失效，文档化），"Add Block" Menu 常驻编辑器上方 | `Features/Editor/RichTextView.swift`、`RichTextBlockView.swift`、`TodoBlockView.swift`、`CodeBlockView.swift`、`ScreenshotBlockView.swift`、`BlockContainer.swift`、`EditorAppBridge.swift` | REFACTOR：Add Block 降权 → 插入点上下文控件 + 菜单/键盘 |
| 设置 | `Settings` 场景 + NSWindow fallback（标题匹配 hack）；分段控件导航（刻意不用 TabView）；四个面板 | `Features/Settings/SettingsView.swift`、`SyncSettingsView.swift`、`FontPreferenceView.swift`、权限面板 | REFACTOR：原生工具栏式标签导航；同步面板重组（FR-053/054 + clarify）；字体单概念呈现 |
| 快捷键 | Carbon `RegisterEventHotKey`；冲突 `kEventHotKeyExists`；录制器（本地 keyDown monitor）；持久化 UserDefaults JSON | `GlobalShortcuts`（SystemBridge）、`ShortcutRecorderRow`（SettingsView.swift）、`LocalPreferences.globalShortcuts.<action>` | REUSE 引擎；UI 保持原生形态（FR-052） |
| 权限 | `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess`/`AXIsProcessTrusted`；懒请求；Settings URL | `PermissionService`（SystemBridge）、权限面板 | REUSE |
| 菜单/命令 | **无任何 `CommandGroup`**；动作都是视图内按钮（New Note ⌘N、Quit ⌘Q 在 footer 等） | `StickyNotesApp.swift`、各视图 | 新增：完整命令体系（FR-072/SC-017） |
| 深链 | `stickynotes://note/<uuid>`/`new`/`search`；`search` 为 no-op | `DeepLinkRouter.swift` | REFACTOR：search 深链补全搜索聚焦 |
| 字体偏好 | `FontPreference`（主字体 Latin + 回退 CJK，默认 Helvetica Neue + PingFang SC），`FontPreferenceView` 呈现为两个字段 | `NoteFontResolver.swift`（App）、`FontPreference.swift`（Domain） | REFACTOR 呈现：单一"笔记字体"概念（FR-055）；存储与键不变 |
| 删除确认 | 卡片上下文菜单含 "Delete Forever"（destructive，无确认）；Empty Trash 确认不可达 | `NoteCardView.swift`、`TrashView.swift` | 补确认（FR-026） |
| Toast | `DeletionToastPresenter`/`DeletionToastOverlay`（2.5 s，VoiceOver 可播报） | `Features/Shared/DeletionToast.swift` | REUSE |

### 1.2 StickyCore（`Packages/StickyCore/Sources/`，7 模块）

| 模块 | 职责 | 关键类型 | 计划影响 |
|---|---|---|---|
| Domain | 领域模型/状态机/摘要/排序键/颜色身份 | `Note`、`BlockKind`、`NoteLifecycle`、`NoteSummary`、`ManualSortKeys`、`NoteColorKey`（canonical hex，FR-040a）、`FontPreference` | REUSE（不改） |
| Persistence | GRDB + FTS5；migrator v1/v2；卡片投影 | `SQLiteNoteRepository`、`CardProjection`（500 行上界）、`SearchService`（limit 100，FTS5 external-content）、`SQLiteWindowStateRepository`、`SQLiteVaultConfigurationStore`、`NoteLifecycle` 30 天 | REUSE（不改） |
| EditorCore | Markdown/IME/空块合并/跨块选择/自动保存 | `MarkdownTransformer`、`AutoSave`（500 ms）、`BlockMergeOperation`、`CrossBlockSelectionCore` | REUSE（不改） |
| AssetStore | 资产字节/缩略图 256px/去重 | `AssetStore`、`ThumbnailGenerator` | REUSE（不改） |
| SecurityCore | Argon2id/AES-GCM/Keychain | `VaultBootstrapService`、`ObjectCrypto`、`KeychainService`（service `local.stickynotes.security`）、`RememberedUnlock`（untilLockOrRestart + boot 时间戳） | REUSE（不改；语义已符合 FR-162a） |
| SyncCore | 单仓库引擎/冲突副本/墓碑/提供者 | `SyncEngine`（actor）、`SyncSummary`（`historyAgedOutDetected`、`conflictCopiesCreated`）、`OfflineReconciler`、`ManifestStore`、`WebDAVProvider`/`S3Provider`、`ProviderError`（`isTransient`） | REUSE（不改） |
| SystemBridge | Carbon 热键/捕获/窗口桥/权限/书签 | `GlobalShortcuts`、`WindowCapture`、`RegionCapture`、`MenuBarWindowFrame`、`NoteWindowBridge`、`WindowLevelBridge`、`DockActivationBridge`、`DisplayChangeBridge`、`PermissionService`、`SecurityScopedBookmarks` | REUSE（不改） |

### 1.3 其他

- `AppTests/` 44 套件；`AppUITests/CriticalFlowsUITests`（5 条，XCUITest，`-UITestSeedNote` 播种）；`Packages/StickyCore/Tests/` 8 目标 92 套件（Swift Testing）。
- `project.yml`（XcodeGen 源）+ 提交的 `StickyNotes.xcodeproj`（objectVersion 77）；部署目标 macOS 26.0；SWIFT_VERSION 6.0；`LSUIElement YES`；App Group `group.local.stickynotes.placeholder`。
- `WidgetExtension/` 6 个 StaticConfiguration 小组件；只链 Domain+Persistence（绝不 SyncCore/SecurityCore）。
- `Prototypes/`：Milestone-0 验证用；**无 Liquid Glass 原型**。
- `Documentation/`：`architecture.md`、`privacy.md`、`security.md`、`toolchain.md`。

## 2. 当前行为基线（必须存活的行为）

1. 菜单栏附属 Library：图标下方 4 pt、左缘对齐、屏内完整、无动画即时开合、点击外部关闭（`MenuBarWindowFrame`，系统 `MenuBarExtra` 窗口）——保留。
2. 点击笔记打开唯一独立窗口；聚焦既有窗口而非新建（`NoteWindowBridge` 注册表）——保留。
3. 关闭窗口只隐藏、不删除；无内容空笔记关闭时自动移除（FR-012/012a）——保留。
4. 笔记窗口不在重启后自动恢复；帧/首选显示器持久化（`SQLiteWindowStateRepository` + `DisplayChangeBridge`）——保留。
5. 每笔记 Always on Top（`.floating`/`.normal`）；不跨 Space、不强压全屏——保留。
6. 自动保存 500 ms 防抖；结构操作即时保存；崩溃契约（最多丢最后防抖窗口）——保留。
7. 排序 4 模式（最近修改/最近创建/标题/手动）；手动序 1024-gap + 64 归一化；排序键 LWW 同步——保留。
8. 搜索：FTS5 覆盖标题/正文/待办/代码/文件名/截图题注；活动笔记过滤；隐私排除；时限 ≤100 ms 起更/10k ≤200 ms——保留。
9. Trash 30 天 + 同步安全门控墓碑清理；冲突副本、永不静默覆盖；删除 toast（2.5 s，VoiceOver）——保留。
10. 同步：单仓库（WebDAV/S3 可选端点）；3.0 s 变更防抖；周期策略 changeOnly/5/15/30/60 分钟；手动同步不阻塞编辑；vault 解锁记忆 = untilLockOrRestart（boot 时间戳比对）；忘记密码不可恢复警告——保留。
11. 全局快捷键 7 项（Carbon）；冲突检测（`kEventHotKeyExists`）；默认剪贴板 ⌘⌥⇧N——保留。
12. 权限：屏幕录制仅捕获时请求；辅助功能仅设置页显式请求（Constitution VI 2.0）；拒绝只降级对应功能——保留。
13. 字体偏好单一存储（主字体 + 回退家族）；每笔记字号 9–24 pt——保留。
14. 性能目标 SC-001/002/003/004a/005/006（150/300/200/16 ms、10k 搜索 200 ms、空闲零 CPU）——保留（FR-091）；不整图解码由 FR-094a/FR-072b 虚拟化保证。
15. 键盘导航（卡片方向键 + Return + ⌘⌫）、上下文菜单（颜色/置顶/导出/移入 Trash 等）、VoiceOver 标签政策（FR-180b）——保留/补全。

### 2.1 差异分类（与规格/澄清决策对比）

| # | 差异 | 分类 | 处理 |
|---|---|---|---|
| D1 | Library 无原生工具栏；顶部是 header 行 + 独立搜索行（两行控制） | C（FR-002/003） | Phase 2 重构成单一原生工具栏 |
| D2 | 卡片 220×160 固定 3/2/1 列（`GridMetricsTests` 编码） | C（FR-021/SC-021/SC-022） | Phase 2 公式化网格 + 密度 |
| D3 | footer（同步状态/Help/About/Settings/Quit）常驻 | C（FR-006/007） | Phase 2 移除；Quit 进应用菜单 |
| D4 | 搜索为自定义字段（非原生搜索体验） | C（FR-003） | Phase 2 原生工具栏搜索 |
| D5 | "Add Block" 常驻编辑器上方首屏控件 | C（FR-043 + clarify：插入点控件+菜单/键盘，无 `/` 命令） | Phase 3 上下文插入 |
| D6 | 设置用分段控件导航（非原生 Settings 导航） | C（FR-050 + clarify：工具栏式标签导航） | Phase 4 原生导航 |
| D7 | 无菜单栏命令（`CommandGroup` 缺失）；Quit 依赖 footer | C（FR-072/SC-017） | Phase 1 命令体系 + 菜单 |
| D8 | "Search All Notes" 全局快捷键与 `stickynotes://search` 为 no-op（仅激活） | B（呈现/行为补全：动作身份不变，聚焦搜索框是动作的自然完成；001 FR-120 动作保留并可改进） | Phase 2 聚焦 Library 搜索框 |
| D9 | 永久删除（卡片 "Delete Forever"）无确认；Empty Trash 确认不可达（死代码 `TrashView`） | C（FR-026 + 001 FR-014b 保留） | Phase 2 补确认对话框 |
| D10 | 内置颜色仅 6 色单值（canonical hex）；无浅/深设计对 | C（FR-030–033） | Phase 1 语义调色板（呈现层，不入库） |
| D11 | 字体面板呈现两个字段（英文/中文），需按 FR-055 呈现单"笔记字体"概念 | B（呈现层；存储不变） | Phase 4 |
| D12 | 设置窗口 fallback 用标题匹配 hack（`title.contains("Settings")`）；`toggleNoteWindows` 标题字符串过滤 | D（不阻塞：保持现状，新增命令体系时改用稳定标识；不扩大改动） | 记录，Phase 6 如有余力再清理 |
| D13 | `sync.historyAgedOut` 目前以静默/弱提示处理（SyncCoordinator 映射为 informational） | B（FR-010/011/012 + clarify ⑥：需显式人话状态"部分同步历史已过期，本地安全"） | Phase 5 状态映射 |
| D14 | 加入既有 vault 目前在同步面板动作区（非高级区） | C（clarify：初始配置 + 高级恢复区重入） | Phase 4/5 重组 |
| D15 | 窗口/工具栏均无 Liquid Glass 呈现（macOS 27 尚未启用） | C（FR-060–063） | Phase 6 原生玻璃集成 |

仅 D12 属 D 类（需行为澄清但**不阻塞**规划：保持现状即满足规格）。

## 3. 工具链与 SDK 验证（实测）

| 项 | 实测值 |
|---|---|
| Xcode | 27.0（27A5228h，beta） |
| macOS SDK | 27.0（`macosx27.0`，唯一 macOS SDK） |
| SDK 路径 | `/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk` |
| Swift | 6.4（target arm64-apple-macosx27.0.0） |
| 部署目标（pbxproj/project.yml） | **macOS 26.0**（规格 out-of-scope 确认保持 macOS 26+） |
| Swift 语言模式 | 6.0，strict concurrency，警告即错误 |
| Testing.framework | 存在（Xcode-beta platform 目录） |
| 构建/测试命令 | 必须前缀 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`（CLT 缺 Testing.framework）；`xcodebuild build -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO`；`swift test --package-path Packages/StickyCore` |

**部署政策（已在规格中决议，不重开）**：最低 macOS 26.0；目标行为按 macOS 27 校验；macOS 27 专属 API（`effectIsInteractive` 27.0、`visibilityPriority` 26.1 等）用 `#available` 守卫，缺失时系统呈现其原生等价外观，**禁止手工仿制玻璃**（FR-062）。Liquid Glass 核心 API 均为 macOS 26.0+，26.0 目标下无"无玻璃"回退问题。

## 4. Apple API Evidence Matrix（已对已装 SDK 声明验证）

来源优先级：已装 SDK 声明（swiftinterface/头文件）> Apple 开发者文档（JSON endpoint 实测）> HIG/技术综述。

| API | 框架 | 已装 SDK 可用 | 最低可用 | 用途 | 为何优于自绘 | 回退（macOS 26.0） | 验证源 |
|---|---|---|---|---|---|---|---|
| `glassEffect(_:in:)` | SwiftUICore | ✅ | macOS 26.0 | 自定义浮动上下文控件（如插入点添加控件、悬浮颜色控件）的玻璃呈现（FR-044 MAY） | 系统玻璃 + 失活/Reduce Transparency 行为自动 | 无（26.0 起可用） | SDK swiftinterface 声明 `glassEffect(_ glass: Glass = .regular, in shape: some Shape)` |
| `Glass`（`.regular/.clear/.identity`；`tint(_:)/interactive(_:)` 为**实例方法**） | SwiftUICore | ✅ | 26.0 | 选择玻璃变体 | — | — | SDK + Apple docs |
| `GlassEffectContainer` | SwiftUICore | ✅ | 26.0 | 相关浮动控件的组呈现（防"无关胶囊"） | — | — | SDK + docs |
| `glassEffectID(_:in:)` / `glassEffectUnion(id:namespace:)` | SwiftUICore | ✅ | 26.0 | 玻璃合并（可选） | — | — | SDK + docs |
| `glassEffectTransition(_:)` | SwiftUICore | ✅ | 26.0 | 玻璃出现/消失动画 | — | — | SDK + docs |
| `sharedBackgroundVisibility(_:)` | SwiftUI | ✅ | 26.0 | 工具栏项玻璃背景控制（ToolbarContent） | — | — | SDK + docs |
| `visibilityPriority(_:)` | SwiftUI | ✅ | **26.1** | 溢出顺序 | — | `#available(macOS 26.1, *)` 守卫；26.0 用默认溢出 | SDK + docs（CI Xcode 26.x 可能无此 API，必须守卫） |
| `EnvironmentValues.appearsActive` | SwiftUICore | ✅ | 10.15+（backDeployed 15.0） | 失活窗口降维（FR-045/FR-063） | — | — | SDK |
| `accessibilityReduceTransparency/Motion`、`accessibilityShowBorders` | SwiftUICore | ✅ | 10.15/11.0 | 环境响应测试与呈现 | — | — | SDK |
| `searchable` | SwiftUI | ✅ | 12.0 | 原生搜索（工具栏 placement 需在 MenuBarExtra 窗口验证） | 系统清空/退出/键盘行为 | NSSearchField（AppKit） | SDK + docs |
| `ToolbarItemPlacement.search` | SwiftUI | ❌ **不存在** | — | — | — | 用 `.searchable(placement:)` 或 NSToolbar+NSSearchField | SDK 未找到（规格未依赖它） |
| `Grid`/`LazyVGrid` | SwiftUI | ✅ | 13.0/11.0 | 卡片网格（沿用 LazyVGrid） | — | — | SDK |
| `NavigationSplitView` | SwiftUI | ✅ | 13.0 | 不采用（FR-005 (a) 已选工具栏目的地） | — | — | SDK |
| `Settings` 场景 | SwiftUI | ✅ | 11.0 | 设置窗口 + TabView 工具栏式标签导航（macOS 14+ 原生形态） | — | 保留现有 NSWindow fallback | SDK |
| `MenuBarExtra` | SwiftUI | ✅ | 13.0 | Library 窗口（沿用，不重写） | — | — | SDK |
| `NSGlassEffectView` | AppKit | ✅ | 26.0 | 如需 AppKit 侧玻璃（27.0 才有 `effectIsInteractive`） | — | `#available` 守卫 | SDK 头文件 |
| `NSButton.BezelStyle.glass` | AppKit | ✅ | 26.0 | AppKit 按钮玻璃（如工具栏项） | — | — | SDK 头文件 |
| `NSBackgroundExtensionView` | AppKit | ✅ | 26.0 | 内容延伸至工具栏/侧边栏下（如需要） | — | — | SDK 头文件 |
| `NSToolbar`/`NSWindowToolbarStyle`/`NSTrackingSeparatorToolbarItem` | AppKit | ✅ | 11.0 | Library 原生工具栏候选方案 | 系统溢出/定制行为 | — | SDK |
| `WindowLevel`、`WindowGroup`、`Window` | SwiftUI | ✅ | 15.0/11.0/13.0 | 窗口语义（沿用） | — | — | SDK |

**未验证/不存在**：`glassEffect(_:in:appliesShadow:cornerRadius:)`（SDK 无此重载，规格未引用——不采用）；`Glass.tint/interactive` 静态属性（实为实例方法，规格写法语义兼容）；`ToolbarItemPlacement.search`（macOS 无，不采用）。**以上全部不作为实现依赖**。

**规格平台约束节的勘误建议（记录，不改规格正文）**：`visibilityPriority` 最低 26.1（26.0 目标需守卫）；`NSGlassEffectView.effectIsInteractive` 最低 27.0。

## 5. 同步状态矩阵研究（来自 SyncCore/SyncCoordinator 代码）

| 引擎状态/错误（真实） | 用户可见状态（七类，clarify B） | 恢复动作（引擎真实支持） | 呈现 |
|---|---|---|---|
| idle/synced；`syncState` 上次成功 | —（正常态零占位） | — | 无 UI（FR-007） |
| 同步进行中（manualSync in progress） | 手动同步显式状态（FR-141b） | — | Sync Now 按钮内状态 |
| `ProviderError`（网络/URLSession，`isTransient`） | ①无法连接仓库（离线/不可达） | 重试（manualSync，非阻塞 FR-153）；自动重连后周期同步 | 横幅 + 重试 |
| 提供者 401/403（认证） | ②认证失败 | 重新验证（testConnection/重新配置凭据）；重试 | 横幅 + 重试/验证动作 |
| vault 未解锁（VaultLocked） | ③需要解锁 | 输入同步密码解锁；可选记忆解锁 | 横幅 + 解锁动作 |
| 有 dirty 本地/待下载（离线中更改） | ④有未同步更改（信息性） | 手动同步 | 横幅可关（FR-010），状态变化重现 |
| `SyncSummary.conflictCopiesCreated` | ⑤已创建冲突副本 | 查看/对比/删除冲突副本（Library 徽标 + 打开） | 横幅 + 查看；卡片警示标识（现有） |
| `SyncSummary.historyAgedOutDetected` → `sync.historyAgedOut` | ⑥同步历史已过期（仅告知，本地安全，无强制动作） | 无需动作；可继续手动同步 | 横幅（muted，非错误色），可关 |
| 解密失败/清单损坏/错误 vault/不兼容版本（fail-closed） | ⑦仓库损坏/不兼容 | 高级：替换仓库 / 加入既有 vault / 移除配置（均需确认） | 横幅 + 高级动作入口 |
| 资产同步失败 | 卡片级 `syncWarning`（现有，保留） | 下轮自动重试；不阻塞笔记 | 卡片徽标（FR-025 保留） |

**冲突模型（代码证实）**：永不静默覆盖；内容分歧 → 冲突副本（标签 `conflict-copy-<ISO8601>-<originDeviceId>`，conflictRecord 去重）；排序键分歧 → LWW；删除 vs 编辑 → 恢复为冲突副本后按删除处理（FR-173）。与 001 FR-170–173 完全一致，重设计不改变。

## 6. 同步动作分类研究（来自代码语义）

| 动作 | 实际语义（代码） | 改本地数据 | 改远程 | 数据丢失风险 | 当前确认 | 分类（新层级） |
|---|---|---|---|---|---|---|
| Sync Now | `manualSync`（非阻塞、幂等、可取消） | 无 | 同步 | 无 | — | Routine（面板主动作） |
| Configure Sync（创建） | `configure`：create vault → Keychain → verify → bootstrap → persist | 写配置 | 建新 vault | 无 | — | Setup（初始流程） |
| Join Existing Vault | `joinExistingVault`：只读探测（fetchMetadata，无 MKCOL）→ openRemoteBootstrap → 单行替换（`replacedFromVaultLocator`）→ 立即同步 | 写配置 | 无（不创建对象） | 无 | 有 | **Setup（初始）+ Recovery（高级区重入）**（clarify D） |
| Replace Repository | `replaceRepository`（FR-154）：本地笔记保留、新 vault 全新引导、不自动删旧远程 | 写配置 | 新建；旧数据保留 | 无（旧 vault 手动清理） | 有确认 | Destructive/Advanced |
| Remove Configuration | `deleteConfiguration`（FR-151）：删本地配置，笔记/远程数据不动 | 删配置 | 无 | 无 | 有确认 | Advanced |
| Export Sync Profile | `SyncProfileCodec`（schema v2，无密钥，v1 兼容，fail-closed） | 无 | 无 | 无（不含密钥） | — | Advanced |
| Export Diagnostic Bundle | `DiagnosticBundleGenerator`（FR-191 正向枚举：版本/错误事件计数，无内容/URL/凭据） | 无 | 无 | 无 | — | Advanced |

## 7. 关键设计决策（供 plan.md 引用）

1. **不引入数据迁移**：调色板、工具栏、网格、横幅全部呈现层；`colorKey`/偏好键/schema 不动（FR-090）。
2. **Library 窗口不重写**：沿用系统 `MenuBarExtra` 窗口（点击外部关闭/定位免费），原生工具栏经既有窗口探针（`MenuBarLibraryWindowProbe`）附加 `NSToolbar`；可行性由 Phase 2 首个 spike 验证（备选：SwiftUI `.toolbar` 若在 MenuBarExtra 窗口可渲染）。
3. **设置导航**：`Settings` 场景 + `TabView`（macOS 14+ 原生工具栏式标签）；保留 NSWindow fallback（LSUIElement 可靠性问题）但不改其内容。
4. **浮动控件玻璃**：仅"插入点添加控件"等自定义交互控件可用 `glassEffect`（FR-044 MAY）；系统组件（菜单、弹出框、工具栏、搜索）由系统自动玻璃——**不为可见而造玻璃**（FR-061）。
5. **命令体系**：新增 `CommandGroup`（File/Edit/View/Window/Help），动作复用既有 model 方法（`LibraryModel`/`NoteWindowCoordinator`），不新建命令管理器。
6. **同步状态呈现**：`SyncStatusPresentation`（App 层）——内部代码 → 七类（spec FR-012）→ 文案/动作；穷举测试。
