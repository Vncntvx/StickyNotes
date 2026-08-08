# Implementation Plan: macOS 27 原生质感重设计（Liquid Glass）

**Branch**: `003-macos27-liquid-glass-redesign` | **Date**: 2026-08-09 | **Spec**: `spec.md`

**Input**: Feature specification from `/specs/003-macos27-liquid-glass-redesign/spec.md` + `/speckit.clarify` 5 项决策 + 仓库/sdk/API 实证（`research.md`）。

## Summary

在既有 001 实现之上做**纯呈现层**现代化：Library 单一原生工具栏 + 公式化自适应卡片网格 + 原生搜索；笔记窗口去 "Add Block" 常驻控件、浮动控件原生玻璃；设置原生工具栏式标签导航；同步状态七类上下文横幅；七色调色板（浅/深双套设计值）；完整菜单/命令体系。StickyCore（领域/持久化/编辑器/安全/同步/系统桥）**零改动**，无数据迁移，无新第三方依赖。部署目标保持 macOS 26.0，macOS 27 行为用已验证 API 呈现（`#available` 守卫 26.1/27.0 专属项），禁止仿制玻璃。

## Technical Context

**Language/Version**: Swift 6.0（语言模式 6、strict concurrency、警告即错误；本机 Swift 6.4 / Xcode 27 beta 27A5228h；CI 意图 Xcode 26.x / Swift 6.3）

**Primary Dependencies**: SwiftUI + AppKit（既有 NSWindow/NSHostingView/Carbon 桥，均已有）；GRDB.swift 7.11.0、SwiftArgon2 1.0.4（既有，不改）；Liquid Glass 用系统 API（SwiftUICore `glassEffect` 等，已对已装 SDK 验证）

**Storage**: GRDB SQLite（App Group `group.local.stickynotes.placeholder`，WAL，migrator v1/v2）；UserDefaults（App Group suite）+ Keychain（service `local.stickynotes.security`）——本特性**全部不变**

**Testing**: Swift Testing（StickyCore 8 目标 92 套件 + AppTests 44 套件）+ XCUITest（AppUITests 5 条）；`DEVELOPER_DIR` 前缀（见 quickstart.md）

**Target Platform**: macOS 26.0+（macOS 27 目标行为）；macOS 专属桌面应用（LSUIElement，菜单栏为主入口）

**Project Type**: desktop-app（macOS，SwiftUI-first + 隔离 AppKit 桥；模块化单体：App + WidgetExtension + StickyCore 7 模块）

**Performance Goals**: 保持 001 SC-001/002/003/004a/005/006（FR-091）：菜单栏暖启 ≤150 ms、卡片 ≤300 ms、新笔记窗口 ≤200 ms、击键 <16 ms、10k 搜索 ≤200 ms、空闲零 CPU（卡片网格不整图解码由 001 FR-094a/FR-072b 虚拟化保证）

**Constraints**: 不改变任何笔记/块/待办/资产/墓碑/同步语义；不新增权限；不新增第三方依赖；无数据迁移；卡片/工具栏等度量由规格公式决定（FR-021/SC-021/SC-022）；macOS 27 专属 API 必须守卫

**Scale/Scope**: 10k 笔记量级（CardProjection 500 行上界、SearchService limit 100、FTS5）；网格虚拟化保持

## Constitution Check

*GATE: 通过。重新评估见 Phase 1 后（本特性不引入架构变更，评估结果不变）。*

| 原则 | 合规 |
|---|---|
| I 聚焦产品 | ✅ 不引入斜杠命令/新块/新功能区；重设计严格限制在呈现层（Out-of-Scope 一致） |
| II 原生 macOS / SwiftUI-first | ✅ 原生组件优先决策链：系统 MenuBarExtra 窗口、NSToolbar/NSSearchField 原生工具栏、系统 Settings 导航；AppKit 仅经既有小桥（窗口探针、NSHostingView、Carbon 热键，均已有） |
| III 本地优先/离线完整 | ✅ 同步引擎不动；横幅重试不阻塞本地编辑（001 FR-153） |
| IV 数据版本化 | ✅ 无 schema/格式变更；无迁移 |
| V 结构化编辑器 | ✅ 块模型/类型/行为全保留；仅插入呈现降权（FR-043） |
| VI 隐私最小权限 | ✅ 不新增权限；权限请求时机不变；诊断边界不变（FR-191） |
| VII/VIII 加密与同步 | ✅ SecurityCore/SyncCore 零改动；冲突/墓碑/单仓库语义不变 |
| IX 文件引用 | ✅ 不触碰 |
| X 可访问/可逆 UX | ✅ 保留全部既有行为基线；永久删除显式确认（FR-026）；颜色非唯一传达（FR-023） |
| XI 性能 | ✅ FR-091 全部目标保留 + 回归测试 |
| XII 测试强制 | ✅ 每阶段含测试；FR-012 穷举、FR-031 对比度、FR-021 公式、SC-017 菜单清单均有自动化 |
| XIII 依赖纪律 | ✅ 零新增第三方依赖 |
| XIV 规格可追溯 | ✅ 任务全部引用 FR/SC/US 编号 |

## Project Structure

### Documentation (this feature)

```text
specs/003-macos27-liquid-glass-redesign/
├── spec.md              # 规格 + Clarifications（5 决策）
├── plan.md              # 本文件（/speckit.plan 输出）
├── research.md          # Phase 0 实证（仓库地图/行为基线/SDK/API 证据/同步研究）
├── data-model.md        # 呈现层数据模型（无持久化变更）
├── quickstart.md        # 验证指南
├── contracts/README.md  # 契约不变声明
└── tasks.md             # /speckit.tasks 输出（后续生成）
```

### Source Code (repository root)

```text
App/Sources/
├── App/                     # StickyNotesApp：+commands 命令体系（Phase 1）
├── Features/
│   ├── DesignSystem/        # 新增（Phase 1）：NotePalette、NoteCardMetrics、Spacing/TypeTokens
│   ├── Library/             # 重构：MenuBarLibraryScene、LibraryCardGrid、NoteCardView；
│   │                        # 替换：LibrarySearchView→原生搜索；SyncStatusView→SyncAttentionBanner
│   │                        # 新增：SyncStatusPresentation、TrashDestinationControls
│   ├── NoteWindow/          # 重构：NoteControlsView（失活/玻璃）、RichTextBlockView（上下文插入）
│   ├── Editor/              # 新增：BlockInsertionControl（插入点上下文控件）
│   └── Settings/            # 重构：SettingsView(TabView)、SyncSettingsView（高级区重组）、FontPreferenceView
├── AppTests/                # 更新 GridMetricsTests/CardRenderingTests 等；新增 FR-012/021/026/031/SC-017 测试
└── AppUITests/              # CriticalFlowsUITests 扩展：工具栏结构/搜索聚焦/Trash 确认
Packages/StickyCore/         # 零改动
WidgetExtension/             # 零改动（行为不回退）
```

**Structure Decision**: 沿用现有模块化单体结构；呈现层新增仅限 `App/Sources/Features/DesignSystem/`（语义令牌与调色板），不新建 manager/service 层（现有 `@Observable` model + SystemBridge 桥已覆盖）。

## Complexity Tracking

无宪法违规（见 Constitution Check），本表留空。

---

# 1. Current Repository Assessment

- **App 层（45 文件）**：组合根 `App/Sources/App/`；4 场景（MenuBarExtra(.window)/Settings/About/Help）；LSUIElement + Dock 切换；无 CommandGroup（动作全在视图内按钮）；手动 NSWindow 桥（笔记窗口/设置/关于/帮助 fallback）；`@Observable` model 模式（LibraryModel/NoteWindowCoordinator/NoteWindowHostModel/SyncCoordinator/DeletionToastPresenter）。
- **Library**：系统 MenuBarExtra 窗口 + `MenuBarLibraryWindowProbe` 定位（4pt/左缘/屏内/无动画）；header（新建 + Notes/Trash 分段）+ 自定义搜索行 + `LazyVGrid`（220×160、3/2/1 列）+ footer（同步状态/Help/About/Settings/Quit）。
- **笔记窗口**：NSWindow（透明隐藏标题栏、红绿灯、`fullSizeContentView`、圆角 8/描边 1）+ NSHostingView + `NoteWindowBridge` 注册表（一笔记一窗口）+ `WindowState` 帧持久化 + `WindowLevelBridge`（置顶）。
- **编辑器**：`NSTextView`（NSViewRepresentable，TextEditor 27 beta 失效的文档化回退）+ 统一块容器（`BlockContainer`）；"Add Block" Menu 常驻编辑器上方（降权目标）；IME/空块合并/跨块选择/自动保存已在 EditorCore 落地。
- **设置**：`Settings` 场景 + NSWindow fallback（标题匹配 hack）；分段控件导航（刻意非 TabView）；快捷键录制器（本地 keyDown monitor + Carbon 注册 + 冲突报错）；同步面板含 Join/Replace/Remove/Export Profile/Export Diagnostic；字体面板两个字段；权限面板状态 + 懒请求。
- **StickyCore（7 模块）**：Domain/Persistence（GRDB v1/v2、FTS5、CardProjection 500 行）/EditorCore/AssetStore/SecurityCore（Argon2id/AES-GCM/Keychain，RememberedUnlock=untilLockOrRestart+启动时间戳）/SyncCore（SyncEngine actor、冲突副本、OfflineReconciler、WebDAV/S3、`SyncSummary.historyAgedOutDetected`）/SystemBridge（Carbon 热键、SCK 捕获、窗口桥、权限、书签）。
- **测试**：AppTests 44 套件（含 GridMetricsTests/CardRenderingTests/LibraryWindowPresentationTests 编码当前视觉常量）、AppUITests 5 条（XCUITest + 种子）、StickyCore 92 套件（性能/迁移/加密/同步全覆盖）。
- **其他**：XcodeGen（project.yml）；WidgetExtension 6 小组件（只链 Domain+Persistence）；Prototypes 无 Liquid Glass 原型；Documentation/architecture|privacy|security|toolchain.md。

详细仓库地图见 `research.md` §1。

# 2. Current Behavior Baseline

必须存活的行为（代码/测试证实）：菜单栏附属窗口语义；一笔记一窗口 + 聚焦既有；关窗不删；空笔记自动移除；窗口不自动恢复但帧持久化；每笔记置顶/不跨 Space；自动保存 500 ms + 崩溃契约；排序 4 模式 + 1024-gap 手动序 + LWW；FTS5 搜索边界（标题/正文/待办/代码/文件名/截图题注，隐私排除，100 行限制）；Trash 30 天 + 同步安全门控；冲突副本不静默覆盖；删除 toast；同步单仓库/3.0 s 防抖/周期策略/手动同步不阻塞/记忆解锁语义/忘密不可恢复警告；7 项全局快捷键 + 冲突检测；权限懒请求与降级；字体偏好单一存储 + 每笔记字号；性能 SC-001/002/003/004a/005/006；键盘导航与 VoiceOver 标签政策。

差异分类（D1–D15，见 `research.md` §2.1）：14 项 C/B 类（11 C + 3 B，呈现/规格要求变更），1 项 D 类（D12 窗口标题匹配 hack——保持现状不阻塞）。**无 A 类缺口需要计划纠偏；无 D 类阻塞项。**

# 3. Clarified Product Decisions

1. **同步状态七类呈现**（FR-012）：按用户动作分组：①无法连接仓库（重试）②认证失败（重新验证）③需要解锁 ④有未同步更改（信息性）⑤冲突副本（查看）⑥历史过期（仅告知，本地安全，001 FR-174）⑦仓库损坏（高级处理）。不平铺引擎内部分类。
2. **块插入途径**（FR-043）：插入点附近微妙添加控件 + 原生菜单/键盘命令；**不引入 `/` 命令**。
3. **删除确认**（FR-026）：移入 Trash 无确认；永久删除（单条 + 清空）显式确认；不新增 Undo 命令。
4. **加入既有 vault**（FR-054）：首次配置流程 + 高级恢复区重入；日常切换走"替换仓库"（FR-154 确认语义）。
5. **设置导航**（FR-050）：System Settings 风格工具栏式标签导航（四面板）。

# 4. macOS 27 / SDK Validation

| 项 | 值 | 证据 |
|---|---|---|
| Xcode | 27.0（27A5228h beta） | `xcodebuild -version` |
| macOS SDK | 27.0（`macosx27.0`，唯一） | `xcodebuild -showsdks` |
| Swift | 6.4 | `swift --version` |
| 部署目标 | **macOS 26.0**（保持） | pbxproj/project.yml `MACOSX_DEPLOYMENT_TARGET = 26.0` |
| Testing.framework | 有（Xcode-beta platform） | 文件系统检查 |
| 构建命令 | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` 前缀 | toolchain.md 既有记录 |

- 部署政策（规格决议，不重开）：macOS 26.0 最低 + macOS 27 目标行为；Liquid Glass 核心 API 均 26.0 起可用；27 专属（`effectIsInteractive` 27.0、`visibilityPriority` 26.1）`#available` 守卫；缺失时系统原生等价外观，禁止手工仿制（FR-062）。
- 记录：本机 SDK 新于 CI（Xcode 26.x）；新 API 使用必须更新 `Documentation/toolchain.md`（任务 T008 延续）。

# 5. Apple API Evidence Matrix

完整矩阵见 `research.md` §4（每项含 SDK 声明/文档 URL）。关键结论：

- **采用（已装 SDK 验证，均 macOS 26.0+）**：`glassEffect(_:in:)`、`Glass`（`.regular/.clear/.identity`；`tint(_:)/interactive(_:)` 实例方法）、`GlassEffectContainer`、`glassEffectID(_:in:)`、`glassEffectUnion(id:namespace:)`、`glassEffectTransition(_:)`、`sharedBackgroundVisibility(_:)`、`appearsActive`、`accessibilityReduceTransparency/Motion`、`accessibilityShowBorders`、`searchable`、`Grid`/`LazyVGrid`、`Settings` 场景、`MenuBarExtra`、`NSToolbar`/`NSWindowToolbarStyle`、`NSButton.BezelStyle.glass`、`NSBackgroundExtensionView`。
- **守卫使用（26.0 目标不可无守卫调用）**：`visibilityPriority(_:)`（26.1）、`NSGlassEffectView.effectIsInteractive`（27.0）。
- **不采用（不存在/无 macOS 形态）**：`glassEffect(_:in:appliesShadow:cornerRadius:)`（SDK 无此重载）、`ToolbarItemPlacement.search`（macOS 无）；`NavigationSplitView`（FR-005 (a) 已选工具栏目的地，不用侧边栏）。
- **验证规则**：实现任务只使用本矩阵内 API；任何新 API 必须先对照已装 SDK 声明 + Apple 文档验证再入任务（Phase 0 已冻结，任务阶段若 SDK 变化需重验并记录）。

# 6. Target UI Architecture

### Library（REUSE 窗口 + REFACTOR 结构）

- **窗口**：沿用系统 `MenuBarExtra`(.window) 场景（点击外部关闭/菜单栏定位/唯一性免费获得，FR-001 语义不变）。窗口探针（`MenuBarLibraryWindowProbe`）复用。
- **工具栏**（FR-002/FR-002a/FR-003/FR-004/FR-005）：单一原生控制行。方案 A（首选）：经窗口探针给 MenuBarExtra 窗口附加 AppKit `NSToolbar`——新建笔记（SF Symbol，⌘N）、原生搜索字段（`NSSearchField` item）、排序（`NSPopUpButton` 或带菜单的 `NSToolbarItem`）、目的地（Notes/Trash 紧凑 `NSToolbarItemGroup` 或分段控件 item）、溢出自动。方案 B（备选，若 MenuBarExtra 窗口不支持 NSToolbar）：SwiftUI `.toolbar` + `.searchable(placement:)`（需 spike 验证渲染）。Phase 2 首个任务为**可行性 spike**，带验收标准，两案均有测试路径。
- **内容区**：`LibraryCardGrid` REFACTOR——`LazyVGrid` 保留，列数/宽度/间距改 FR-021 公式（DesignSystem `NoteCardMetrics`），高度内容驱动 72–128（SC-022）；`CardProjection` 数据源不变。
- **导航**：Notes/Trash 经工具栏目的地控件（FR-005 (a)）；Trash 仍是 grid scope + Trash 目的地视图（Empty Trash + 确认在此呈现，复活 `TrashView` 的确认逻辑）。
- **状态**：footer 移除（FR-006/007）；同步注意态以 `SyncAttentionBanner`（Phase 2 壳 + Phase 5 完整七类映射）呈现于内容区顶部（决策：横幅固定置于内容区顶部——spec FR-010 "就近横幅或内联"的落地选择，2026-08-09）；Help/About/Settings/Quit 全部进入菜单（Phase 1 先落）。
- **搜索聚焦**：`searchAll` 全局快捷键与 `stickynotes://search` 从"仅激活"补全为"打开 Library + 聚焦搜索框"（D8，行为补全）。

### Note Window（REUSE，仅呈现调整）

- 窗口/桥/持久化全部保留（`NoteWindowCoordinator`/`NoteWindowBridge`/`WindowState`）。
- FR-043：`RichTextBlockView` 顶部常驻 "Add Block" Menu 移除 → 新增 `BlockInsertionControl`（插入点附近微妙控件，`glassEffect` 呈现 MAY）+ 菜单/键盘命令（⌘⇧T/⌘⇧C 保留；新增"添加块"子菜单在 Edit/Insert）。
- FR-044/045：悬浮控件（颜色/添加/格式）出现/隐藏时机不变；玻璃呈现仅用于自定义控件；失活态用 `appearsActive` 驱动的系统化外观（禁止保留强调色）。
- 首行定位/获焦（FR-042）与紧凑尺寸可用性（FR-071）已满足，保持并加回归。

### Settings（REFACTOR 导航）

- `Settings` 场景 + `TabView`（macOS 14+ 原生工具栏式标签导航；clarify 决策 5）替换分段控件；`NSWindow` fallback（LSUIElement 可靠性）保留但内容同步更新。
- 面板：General（Dock + 快捷键录制，原生形态，FR-052）、Sync（FR-053 + 高级区 FR-054 + 加入既有 vault 定位 clarify 4）、Fonts（单"笔记字体"概念 + 系统回退 + 中英混排预览，FR-055；存储键不变）、Permissions（FR-056，呈现保留）。

**首次配置入口规则（实现决议）**: 同步配置不存在时，同步面板默认页同时呈现 "Configure Sync" 与 "Join Existing Vault" 两条初始路径；配置存在后 "Join" 仅保留高级区恢复重入（tasks T050/T057）。
- 窗口尺寸：面板高度适配内容（FR-051），不再用固定 480×540 画布。

### Commands / Menus（新增，Phase 1）

- 新增 `CommandGroup`：File（新建笔记 ⌘N、剪贴板新建、区域截图到新笔记、窗口截图到新笔记、移入 Trash ⌘⌫、永久删除、关闭窗口 ⌘W）、Edit（标准编辑 + 添加待办 ⌘⇧T/代码块 ⌘⇧C）、View（搜索 ⌘F 聚焦、显示/隐藏笔记窗口、排序子菜单）、Window、Help（帮助、关于——About 在应用菜单）。
- 动作复用既有 `LibraryModel`/`NoteWindowCoordinator`/`SyncCoordinator` 方法；**不新建命令管理器**；键盘兼容既有快捷键（D7/C）。
- **辅助模式可达性（Constitution X）**：LSUIElement 无可见应用菜单；footer 移除后，Settings/About/Help/Quit 必须经菜单栏图标可达。方案：(a) MenuBarExtra 下拉菜单场景（含"打开 Library"项——需 spike 验证与 FR-001 点击即开窗语义的协调），或 (b) 附加 `NSStatusItem` 下拉菜单；纳入 T018 spike 验收或新增任务；T015/T024 双态断言（Dock 显示/隐藏）。
- SC-017 清单校验：每个重要工具栏命令有菜单命令。

### Window Management（沿用，见第 19 节矩阵）

# 7. Liquid Glass Usage Map

**功能/控制层（采用）**：

| 位置 | 系统组件/API | 功能目的 | 失活窗口 | Reduce Transparency | Increase Contrast/Show Borders | Dark Mode |
|---|---|---|---|---|---|---|
| Library 工具栏 | `NSToolbar`（系统窗口玻璃） | 导航/控制 | 系统自动降维 | 系统自动雾化 | 系统自动边框 | 系统自动 |
| 菜单栏/菜单/弹出框/搜索 | 系统组件（自动玻璃） | 导航/命令 | 系统处理 | 系统处理 | 系统处理 | 系统处理 |
| 设置窗口工具栏 | `Settings` + TabView（系统形态） | 面板导航 | 系统处理 | 系统处理 | 系统处理 | 系统处理 |
| 插入点块插入控件（自定义） | `glassEffect(_:in:)` + `GlassEffectContainer`（FR-044 MAY） | 块插入入口 | `appearsActive` 驱动隐藏/降维 | 系统雾化 | 保持边框可辨（`accessibilityShowBorders`） | 系统自动 |
| 笔记窗口悬浮控制（自定义，如需要） | `glassEffect`（仅自定义控件；多数用系统 Menu/Popover 替代） | 颜色/添加/格式 | 失活不显示或失活外观（FR-044） | 系统雾化 | 不依赖半透明可辨（FR-062） | 系统自动 |

**不使用 Liquid Glass 的表面（明确列出）**：笔记内容/编辑器表面/块内容、笔记背景（笔记色不透明内容层）、Library 卡片、预览、设置表单内容、Trash 内容、About/Help 内容——全部保持内容层（FR-022/FR-041/FR-060/FR-061）。

**呈现原则**：不为"可见玻璃"造玻璃；系统组件零成本自动玻璃；仅自定义交互控件 MAY 玻璃；无玻璃叠玻璃；clear 玻璃不用作默认（FR-061）。

# 8. Data and State Architecture Impact

- **不变**：SQLite schema（v1/v2）、`colorKey`/`customColor`、全部偏好键、Keychain 项、同步契约（contracts/README.md）、`StickyCore` 全部模块。
- **新增（App 层运行时呈现模型，不入库）**：`NotePalette`（七色浅/深设计值，FR-030–033）、`NoteCardMetrics`（FR-021/SC-021/SC-022 常量）、`SyncStatusPresentation`（七类映射，FR-012）、`BlockInsertionControl` 状态。
- **呈现依赖**：`ReadableTheme.projecting`（前景自动调整）改读 `NotePalette` 实际渲染值（FR-033）；卡片背景改读调色板（FR-022）。
- **状态流**：`SyncCoordinator` 状态/SyncSummary 标志 → `SyncStatusPresentation` 映射 → `SyncAttentionBanner`；横幅可关、状态不变不重现、新类别重现（FR-010）。

# 9. Sync UX Architecture

**Sync State Matrix**（引擎真实状态 → 七类 → 动作，详见 `research.md` §5）：

| 引擎状态/错误（代码证实） | 用户可见（七类） | 动作（引擎真实支持） | 呈现 |
|---|---|---|---|
| idle/已同步 | — | — | 零占位（FR-007） |
| 手动同步进行中 | 显式进度（FR-141b） | — | Sync Now 状态 |
| `ProviderError` 瞬时（离线/不可达） | ①无法连接仓库 | 重试（manualSync，非阻塞） | 横幅 + 重试 |
| 提供者 401/403 | ②认证失败 | 重新验证凭据（testConnection/配置）；重试 | 横幅 + 动作 |
| vault 未解锁 | ③需要解锁 | 输入同步密码（可选记忆解锁） | 横幅 + 解锁 |
| 离线更改未上传/待下载 | ④有未同步更改 | 手动同步 | 横幅可关 |
| `conflictCopiesCreated` | ⑤冲突副本已创建 | 查看（打开既有冲突副本笔记窗口，001 语义）/对比/删除（卡片徽标已有） | 横幅 + 查看 |
| `historyAgedOutDetected` → `sync.historyAgedOut` | ⑥历史过期（仅告知） | 无需动作 | 横幅（muted，可关） |
| 解密失败/清单损坏/错误 vault/版本不兼容 | ⑦仓库损坏/不兼容 | 高级：替换/加入/移除（均确认） | 横幅 + 高级入口 |
| 资产失败 | 卡片级 `syncWarning`（保留） | 下轮自动重试 | 卡片徽标 |

**多类别优先级（实现决议，2026-08-09）**: 多类别同时活跃时，`SyncStatusPresentation` 按确定性顺序呈现最高优先者：⑦仓库损坏/不兼容 > ③需要解锁 > ②认证失败 > ①无法连接 > ⑤冲突副本 > ④有未同步更改 > ⑥历史过期。理由：数据可恢复性/用户必须动作优先于信息性；纯函数解析，由 FR-012 穷举测试断言（tasks T051）。

**映射实现**：`SyncStatusPresentation`（App 层新类型）——输入 SyncCoordinator 暴露状态 + SyncSummary 标志 + sanitized codes；确定性映射，穷举测试（zh-Hans/en，无内部标识符，FR-012/SC-012）。

**同步设置层级**（FR-053/054 + clarify 4）：默认页（状态/提供商/上次同步/自动同步/频率/记忆解锁/同步现在）→ 高级区（替换仓库/移除配置/加入既有 vault 恢复重入/导出同步配置/导出诊断包；破坏性操作确认）。动作分类见 `research.md` §6（Routine: Sync Now；Setup: Configure/Join；Recovery: Join 重入；Advanced: Export*；Destructive: Replace/Remove——均已有确认语义，仅重新组织 + 补单条永久删除确认 FR-026）。

# 10. Migration Strategy

**无迁移**。迁移清单与理由见 `research.md` §7 + `data-model.md`"迁移清单（无）"：调色板/网格/工具栏/横幅/导航均为呈现层；`colorKey` 语义映射在呈现层完成（FR-032）；偏好键零更名。验证：001 迁移夹具（历史 schema 内存重建 + `Fixtures/`）继续全绿；升级路径"旧数据 + 新 UI"夹具测试（FR-090/SC-025）在 Phase 7。

# 11. Accessibility Strategy

- **继承原生**：工具栏（NSToolbar item 自带标签）、搜索（NSSearchField 系统无障碍）、菜单命令、设置表单（Form/Section/Toggle/Picker）——用平台默认标签，不重建语义（001 FR-180b 政策延续）。
- **自建控件**（卡片选择、插入点控件、同步横幅、快捷键录制器）：明确本地化标签与状态（FR-180b 既有测试扩展）。
- **键盘**：卡片方向键 + Return + ⌘⌫（FR-024，补实现与测试）；完整键盘可达菜单命令（SC-017）；录制器全程键盘（FR-052 既有）。
- **选择/状态不以颜色为唯一传达**：卡片选择态（FR-023）、同步状态（图标+文字+颜色）、冲突徽标（图标+文字）——既有模式延续。
- **配色可访问**：调色板浅/深全组合对比度断言（FR-031 + 001 FR-042 阈值）；自定义颜色 + 透明度 + Increase Contrast 前景自动调整（FR-033）。
- **环境响应**：`appearsActive`（失活降维 FR-045）、Reduce Transparency/Motion、Increase Contrast/Show Borders（`accessibilityShowBorders` 等环境键）断言（FR-062/063）；VoiceOver 播报横幅三要素与删除结果（既有 toast 机制复用）。

# 12. Testing and Regression Strategy

- **单元（App 层新增/更新）**：FR-012 七类映射穷举（无泄漏/双语言）；FR-021 列数公式（各宽度确定性）；FR-031 调色板对比度（七色 × 浅/深 × 主/次/控件）；FR-032 迁移映射 + 自定义原值；FR-026 确认状态机；SC-017 菜单清单校验；搜索聚焦行为。
- **集成**：既有 001 全量回归（92 + 44 套件）；`GridMetricsTests`/`CardRenderingTests`/`LibraryWindowPresentationTests` 更新为新度量（这是呈现行为变更的显式测试迁移，非回归）；窗口/快捷键/权限/同步组合既有套件保持。
- **UI（AppUITests 扩展）**：Library 单工具栏无底部栏无 Quit；新建即打字；搜索聚焦（全局快捷键）；Trash 目的地 + 永久删除确认；设置四面板导航；同步横幅（种子状态）——沿用 `-UITestSeedNote` 播种模式。
- **手动视觉 QA 矩阵**（Phase 7）：浅/深、激活/失活、系统强调色、Reduce Transparency/Motion、Increase Contrast/Show Borders、显示比例、320 pt 与宽 Library、紧凑笔记窗口、多笔记窗口、纯键盘、VoiceOver。**不依赖截图断言原生玻璃**（系统材质随 OS 渲染变化；测行为与层级，不测像素）。
- **回归基线**（Phase 0 先补后改）：既有笔记加载、加密仓库打开、同步仍工作、笔记 ID 不变、Trash 可恢复语义、快捷键存活、字体偏好存活、笔记窗口重开、自动保存、捕获快捷键、权限拒绝不崩溃、无双窗口。

# 13. Performance Considerations

- 数据路径零变化：`CardProjection` 500 行上界、FTS5 增量索引、懒缩略图——原样。
- 新呈现开销受控：调色板为常量查找；`SyncStatusPresentation` 纯函数；横幅单例观察（不每卡片轮询）；网格公式为纯计算。
- 玻璃由系统渲染（零手绘图层，FR-091/SC-006）；插入点控件惰性出现。
- 已知风险（不因重设计新增，记录）：MenuBarExtra 窗口 + NSToolbar 是否引入显示开销——spike 验证；`visibilityPriority` 守卫分支无性能影响。
- 回归：`PerformanceBaselineTests`/`SearchPerformanceTests`/`KeystrokeLatencyTests` + Instruments 人工抽查（SC-024）。

# 14. File-by-File Change Map

**REUSE 分类（StickyCore 全部、WidgetExtension 全部、窗口桥/编辑器核心/捕获/权限/快捷键引擎/字体存储/Toast/EmptyStateView）——零改动。**

**REFACTOR**：

| 路径 | 当前职责 | 计划修改 | 风险 | 受影响测试 |
|---|---|---|---|---|
| `App/Sources/App/StickyNotesApp.swift` | 场景/入口/快捷键布线/窗口 fallback | +`commands` 命令体系；移除对 footer 的依赖；searchAll/深链行为补全 | 中 | AppLogicTests、新增 SC-017 清单测试 |
| `App/Sources/Features/Library/MenuBarLibraryScene.swift` | Library 结构（header/搜索/网格/footer） | 结构改为原生工具栏 + 内容区；移除 footer | 中 | LibraryWindowPresentationTests、UI 测试 |
| `App/Sources/Features/Library/LibraryCardGrid.swift` | LazyVGrid 固定列 | FR-021 公式化 + 密度 + 键盘导航 | 中 | GridMetricsTests（更新）、新增 FR-021 测试 |
| `App/Sources/Features/Library/NoteCardView.swift` | 卡片 220×160 呈现 | 调色板取值 + 密度适配 + 选择态 | 低 | CardRenderingTests（更新） |
| `App/Sources/Features/Library/LibraryModel.swift` | 数据加载/动作 | Trash scope 确认动作接入（FR-026）；搜索聚焦入口 | 低 | RetrievalIntegrationTests 等 |
| `App/Sources/Features/NoteWindow/NoteWindowHostModel.swift` | 笔记窗口 VM | 无结构变化（如需随 FR-026 接确认） | 低 | NoteWindowLifecycleTests |
| `App/Sources/Features/NoteWindow/NoteControlsView.swift` | 悬浮控制栏 | 失活外观（appearsActive）、玻璃呈现（MAY） | 低 | AppearanceIntegrationTests |
| `App/Sources/Features/Editor/RichTextBlockView.swift` | 编辑器 + Add Block Menu | 移除常驻 Add Block；接入插入点控件 | 中 | BlockPresentationConsistencyTests、EditorBlockEditingTests |
| `App/Sources/Features/Settings/SettingsView.swift` | 分段控件四面板 | TabView 工具栏式导航；快捷键录制器保留 | 低 | AppLogicTests |
| `App/Sources/Features/Settings/SyncSettingsView.swift` | 同步面板 + 动作区 | 高级区重组（FR-054 + clarify 4）；七类状态接入 | 中 | SyncCompositionTests、新增映射测试 |
| `App/Sources/Features/Settings/FontPreferenceView.swift` | 英文/中文两字段 | 单"笔记字体"概念 + 混排预览（存储不变） | 低 | FontPreferenceApplicationTests |
| `App/Sources/Features/Trash/TrashView.swift` | 死代码 | 复活为 Trash 目的地视图（Empty Trash 确认）或并入 grid scope 后删除 | 低 | UnifiedEmptyStateTests |
| `App/Sources/Features/NoteWindow/ReadableTheme.swift` | 前景对比投影 | 改读 NotePalette | 低 | AppearanceIntegrationTests |

**REPLACE**：

| 路径 | 原因（规格要求） | 风险 | 测试 |
|---|---|---|---|
| `App/Sources/Features/Library/LibrarySearchView.swift` | 自定义搜索字段 → 原生搜索（FR-003） | 中 | SearchWiringTests、UI 测试 |
| `App/Sources/Features/Library/SyncStatusView.swift` | 常驻 footer → 注意态横幅（FR-006/007/010） | 中 | 新增 FR-010/012 测试、UI 测试 |

**新增**：

| 路径 | 职责 | 理由 |
|---|---|---|
| `App/Sources/Features/DesignSystem/NotePalette.swift` | 七色浅/深设计值 + 迁移映射 + 对比度元数据 | 单一语义颜色来源（FR-030–033），避免散落字面量 |
| `App/Sources/Features/DesignSystem/NoteCardMetrics.swift` | FR-021/SC-021/SC-022 常量与公式 | 确定性网格可测试 |
| `App/Sources/Features/DesignSystem/AppMetrics.swift` | 间距/排版语义令牌（克制集） | 跨窗口一致性（FR-080），不覆盖系统度量 |
| `App/Sources/Features/Library/SyncStatusPresentation.swift` | 七类映射（纯函数） | FR-012 可穷举测试 |
| `App/Sources/Features/Library/SyncAttentionBanner.swift` | 注意态横幅视图 | FR-010 |
| `App/Sources/Features/Editor/BlockInsertionControl.swift` | 插入点块插入控件 | FR-043（+ 菜单/键盘命令） |

# 15. Implementation Phases

每阶段独立可构建、可回归、可验收。

**Phase 0 — 基线安全**（依赖：无）
- 全量回归基线（quickstart.md 命令）；冻结 SDK/API 证据（本计划 §4/§5 已落）；行为基线文档化（research.md §2）；补缺失回归测试（若运行暴露）；确认迁移假设（无迁移）。
- 完成标准：92+44+5 全绿；`git diff` 无代码改动。

**Phase 1 — 共享原生呈现基础**（依赖：Phase 0）
- `DesignSystem`（NotePalette + 对比度测试 FR-031/032、NoteCardMetrics、AppMetrics）；`ReadableTheme` 接入调色板；菜单/命令体系（`commands` + SC-017 测试）——先落菜单使 footer 移除不损失入口；无障碍基础（键盘导航框架、标签政策）。
- 完成标准：Phase 1 测试绿；浅/深调色板断言通过；Quit/Settings/Help/About 可经菜单到达；SC-017 清单通过。

**Phase 2 — Library**（依赖：Phase 1）
- 任务 1：**原生工具栏可行性 spike**（MenuBarExtra 窗口 + NSToolbar vs SwiftUI .toolbar；验收：项目显示、溢出、键盘可达、点击外部关闭不回归；记录决策）。其后：单一原生工具栏（新建/搜索/排序/目的地）、footer 移除、自适应网格（FR-021/SC-021/022）、卡片密度与选择/悬停/上下文、键盘导航、Trash 目的地 + Empty Trash/永久删除确认（FR-026）、搜索聚焦（D8）、横幅壳（基本注意态）、GridMetricsTests 等更新。
- 完成标准：US1/US6 相关验收 + SC-005/006/007/008/021/022/023 通过；AppUITests 扩展绿。

**Phase 3 — 独立笔记窗口**（依赖：Phase 1）
- Add Block 降权 → `BlockInsertionControl` + 菜单/键盘；悬浮控件失活外观与玻璃呈现（MAY）；紧凑尺寸回归；内容定位/获焦回归。
- 完成标准：US2 验收 + SC-003/004 通过；既有 NoteWindowLifecycle 套件绿。

**Phase 4 — 设置**（依赖：Phase 1）
- TabView 工具栏式导航替换分段控件；General/快捷键原生形态（FR-052）；Fonts 单概念（FR-055）；Permissions 呈现（FR-056）；同步面板默认页重组（FR-053）。
- 完成标准：US4 验收 + SC-011 通过；FontPreference/Settings 套件绿。

**Phase 5 — 同步 UX**（依赖：Phase 2 横幅壳）
- `SyncStatusPresentation` 七类映射 + 穷举测试；横幅完整化（可关/重现语义）；高级区重组（替换/移除/加入重入/导出×2 + 确认）；诊断边界回归。
- 完成标准：US5 验收 + SC-012/013 通过；FR-012 穷举测试绿。

**Phase 6 — macOS 27 精修**（依赖：Phase 2/3/4）
- 验证过的玻璃集成（工具栏系统玻璃自动；插入点控件 glassEffect；`appearsActive` 失活降维）；`visibilityPriority`（26.1 守卫）/27 专属项按可用性接入；窄宽溢出；Reduce Transparency/Motion/Contrast 断言；最终原生行为审查（D12 有余力再清理）。
- 完成标准：US6/SC-009/010/014/015/016/018/019 通过。

**Phase 7 — QA 与迁移验证**（依赖：Phase 0–6）
- 旧数据/旧仓库夹具验证（SC-020/025）；视觉 QA 矩阵（§12）；性能回归（SC-024）；全量回归 + 无障碍走查。
- 完成标准：SC-001..025 全通过；无未解决缺陷。

# 16. Technical Decision Records

| 决策 | Context | 备选 | 选择 | 理由 | 权衡 | 兼容影响 |
|---|---|---|---|---|---|---|
| Library 窗口架构 | 规格要求保留菜单栏附属语义 | 自定义 NSPanel 重写 | 沿用系统 MenuBarExtra 窗口 + 探针 | 点击外部关闭/定位/唯一性系统免费；最小重写 | NSToolbar 附加需 spike 验证 | 无（FR-001 不变） |
| Library 工具栏实现 | 单一原生工具栏（FR-002） | SwiftUI .toolbar | AppKit NSToolbar（方案 A）+ SwiftUI 备选（方案 B） | 原生窗口工具栏行为/溢出/无障碍 | 菜单栏窗口内附加工具栏存在不确定性 → spike 先行 | 无 |
| 搜索实现 | FR-003 原生搜索体验 | 保留自定义字段 | NSSearchField（工具栏）或 .searchable | 系统清空/退出/键盘行为 | 与 MenuBarExtra 窗口兼容性待 spike | 无 |
| 设置导航 | clarify 5 工具栏式标签 | 分段控件/侧边栏 | Settings 场景 + TabView | macOS 14+ 原生形态；四浅层类目最轻 | 保留 NSWindow fallback | 无 |
| 块插入 UI | clarify 2：插入点控件 + 菜单/键盘，无 `/` | 斜杠命令/仅菜单 | BlockInsertionControl + 菜单命令 | 最小改动；不引入新输入机制 | 发现性依赖悬停/上下文 | 无（编辑器核心不动） |
| 调色板表示 | FR-030–033 浅/深双套 | 改 Domain 存储值 | App 层 NotePalette 常量 + colorKey 不变 | 身份值入库不动（FR-090）；呈现映射可测 | 001 对比度测试基于 canonical hex，需在呈现层新增断言 | 零（无迁移） |
| 同步状态呈现 | clarify 1 七类 | 引擎全分类平铺 | SyncStatusPresentation 纯函数映射 | 用户按动作理解；FR-012 穷举 | 映射需随引擎新错误维护（测试门禁） | 无 |
| 命令体系 | FR-072/SC-017 无 CommandGroup | 各视图各自按钮（现状） | 新增 commands 复用既有 model 方法 | 单一命令源；键盘/菜单/工具栏同构 | 需防重复命令入口 | 键盘兼容既有 |
| 部署/回退 | macOS 26.0 目标 + 27 行为 | 27-only | 26.0 + `#available` 守卫（26.1/27.0 项） | 规格决议；Liquid Glass 核心 26.0 起可用 | 27 专属微效缺失（可接受） | CI Xcode 26.x 编译安全 |
| 窗口恢复 | FR-007/032 既有 | 自动恢复窗口 | 保持（不自动恢复 + 帧持久化） | 既有行为基线 | — | 无 |
| 搜索聚焦补全 | D8 searchAll 为 no-op | 保持 no-op | 打开 Library + 聚焦搜索框 | "搜索全部笔记"语义的自然完成；001 FR-120 动作不变 | 轻微行为改进（B 类） | 无 |

# 17. Risk Register

| 风险 | 可能性 | 影响 | 缓解 | 验证 |
|---|---|---|---|---|
| macOS 27 SDK beta API 不稳定（glassEffect 族） | 中 | 高（视觉核心） | 只依赖已装 SDK 验证声明；实现期重验；DesignSystem 单点替换 | Phase 0 证据冻结 + 每任务对照 SDK |
| MenuBarExtra 窗口不支持 NSToolbar/.searchable | 中 | 高（Library 架构） | Phase 2 spike 先行；备选方案 B；极端备选：转换窗口架构（需评估 FR-003 点击外部关闭回归） | spike 验收标准（项目显示/溢出/键盘/关闭） |
| `visibilityPriority`(26.1)/`effectIsInteractive`(27.0) 在 CI Xcode 26.x 编译失败 | 中 | 中 | `#available` 守卫 + toolchain.md 记录 | CI 编译回归 |
| 自定义窗口行为 × 新标题栏/材质交互 | 低 | 中 | 不改窗口创建路径；仅呈现层调整 | 窗口套件回归 |
| 持久化迁移风险 | 低 | 高 | 无迁移；schema 零改动 | 迁移测试 + 夹具验证（Phase 7） |
| 同步回归 | 低 | 高 | SyncCore 零改动；映射只读输入 | SyncCore 全量 + SyncCompositionTests |
| 加密/配置丢失 | 低 | 高 | Keychain/配置路径零改动；确认语义保留 | SecurityCore 套件 + FR-090 夹具 |
| 全局快捷键回归 | 低 | 中 | 引擎 REUSE；仅 UI 呈现 | ShortcutConfigurationTests + GlobalShortcutTests |
| 权限行为变化 | 低 | 中 | 请求时机零改动 | PermissionFallbackIntegrationTests |
| 大量笔记性能 | 低 | 中 | 数据路径不变；新增呈现实测 | PerformanceBaselineTests + SC-024 |
| 彩色笔记对比度 | 中 | 中 | FR-031 断言 + FR-033 自动调整 | 对比度测试（浅/深 × 七色 × 组合） |
| 失活窗口外观 | 中 | 中 | appearsActive 驱动 + 系统组件自动 | AppearanceIntegrationTests + 人工 QA |
| UI 测试依赖系统材质渲染 | 中 | 低 | 不依赖截图断言玻璃；测行为/层级 | 测试策略（§12） |

# 18. Open Technical Questions

1. MenuBarExtra 窗口是否支持附加 AppKit NSToolbar / SwiftUI `.toolbar` / `.searchable`——**Phase 2 spike 任务回答**（有明确验收标准与备选方案，不阻塞 Phase 0/1）。
2. macOS 26.0 目标下 `Settings` 场景 + `TabView` 在 LSUIElement 应用中的渲染可靠性——Phase 4 验证；已有 NSWindow fallback 兜底。
3. App Group 正式命名（`group.local.stickynotes.placeholder`）——001 遗留问题，与 003 无关，不阻塞（任务列表外）。

其余全部由仓库检查、规格、已装 SDK 声明或 Apple 文档回答。无产品决策遗留。

# 19. Ready-for-Tasks Checklist

- [x] 当前架构已检查（research.md §1：App/StickyCore/测试全量盘点）
- [x] 当前行为基线已记录（research.md §2 + 差异分类 D1–D15，无 D 类阻塞）
- [x] 部署目标已解决（macOS 26.0 保持；27 行为 + 守卫策略）
- [x] Liquid Glass API 已逐项对已装 SDK 验证（research.md §4 证据矩阵）
- [x] 无发明 Apple API（未验证项全部剔除：appliesShadow 重载、ToolbarItemPlacement.search）
- [x] 原生组件选择已确立（NSToolbar/searchable 决策链 + spike 门禁）
- [x] Library 架构已确立（MenuBarExtra 沿用 + 原生工具栏 + FR-021 网格 + 横幅）
- [x] Note Window 架构已确立（REUSE + Add Block 降权 + 失活/玻璃呈现）
- [x] Settings 架构已确立（TabView 工具栏式标签 + 四面板 + 高级区重组）
- [x] 同步恢复语义已由代码验证（SyncCore/SyncCoordinator → 七类映射，含 historyAgedOut）
- [x] 迁移影响已确定（无迁移；呈现层全映射）
- [x] 数据丢失风险已处理（schema/偏好/Keychain 零改动；破坏性操作确认 FR-026/054）
- [x] 无障碍计划已建立（§11 + 既有 FR-180b 政策延续）
- [x] 测试策略已建立（§12：单元/集成/UI/手动矩阵 + 回归基线）
- [x] 实现阶段独立可构建（Phase 0–7，每阶段完成标准明确）
- [x] 文件级影响已理解（§14 Change Map，REUSE/REFACTOR/REPLACE 分类与理由）
- [x] 无未解决产品设计决策（5 项 clarify 全部落地；Open Questions 仅 spike/验证类）

**结论：可进入 `/speckit.tasks`。** 唯一实现期门禁：Phase 2 spike（原生工具栏可行性）有明确备选方案，不构成阻塞。
