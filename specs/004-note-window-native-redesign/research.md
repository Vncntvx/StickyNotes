# Research: 独立笔记窗口原生镀铬与自适应重设计（004）

**Branch**: `004-note-window-native-redesign` | **Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md)

本文件记录 /speckit.plan Phase 0 的调研结论：代码库实地勘查 + 已安装 SDK（Xcode 27 beta 27A5228h / macOS 27）API 证据。所有 API 断言均来自本机 SDK 头文件 / swiftinterface，非记忆或第三方来源。

## 1. 代码库现状（勘查结论，均含 file:line 证据）

### 1.1 窗口层（App/Sources/Features/NoteWindow/）

- **NoteWindowCoordinator.swift（657 行）**同时承担：窗口创建（`open(noteId:)`，:158-244）、`NoteWindowContent` 根视图定义（:408-657）、`NoteWindowDelegate`（:345-403）、菜单派发（:111-155）、显示变化重应用（:318-337）。
- 窗口创建 :173-204：`styleMask = [.titled, .closable, .miniaturizable, .resizable]`（**无 `.fullSizeContentView`**）、`titlebarAppearsTransparent = true`、`titleVisibility = .hidden`（:189-191，标题刻意隐藏）、不透明 `backgroundColor`（:192）、`isReleasedWhenClosed = false`（:193）、**`contentMinSize = 300×200`**（:201，注释明确为迁就控件行）。
- **已提交的红灯测试** `AppTests/NoteWindowLifecycleTests.swift:114` 断言 `styleMask.contains(.fullSizeContentView)`，当前**失败**（实测：AppKit 不会自动补位）；测试注释 :92-97 指出本重设计应使其转绿。
- **既有缺陷**：红绿灯/`window.close()` 路径（`windowWillClose` :371-383）只 `releaseWindowDelegate`（丢 delegate + host，:288-291），**从不 `NoteWindowBridge.unregister`**；`isReleasedWhenClosed = false` 使窗口滞留 `NSApp.windows`，`open(noteId:)` 的 `focusExisting` 分支（:161-163）会复活宿主已死的旧窗口 → `updateNotePaper`/`updateAlwaysOnTop`/菜单派发静默失效。⌘W 路径（`StickyNotesApp.closeKeyNoteWindow` :554-564）是唯一 close+unregister+release 都做的路径。
- 帧持久化：`NoteWindowDelegate.saveFrame`（:385-402）→ `SQLiteWindowStateRepository.updateFrame`（设备本地 `windowState` 表，永不同步）；恢复 `restoredFrame(for:)` :301-314 + `DisplayChangeBridge.correctedFrame`。
- 置顶路径（单一权威）：`NoteControlsView` → `onChanged` → `host.updateAppearance`（立即持久化）→ `coordinator.updateNotePaper` + `updateAlwaysOnTop`（:276-284：`WindowLevelBridge.apply` + `NoteWindowBridge.applyCollectionBehavior` + pin 时 `orderFrontRegardless`）。`WindowLevelBridge.level(alwaysOnTop:)` 纯函数 + `apply`（SystemBridge，26 行）。
- `NoteWindowBridge`（SystemBridge）：弱引用注册表 + `collectionBehavior`；`allRegistrations()` 被 ⌘W 使用。
- **应用内零 NSToolbar 使用**：唯一一次尝试是 Library 的 MenuBarExtra 窗口 spike（`MenuBarLibraryScene.swift:11-22`，提交 36057dd 放弃）——该窗口是私有的 MenuBarExtraWindow（无边框），**与标准 NSWindow 无关**，不构成 NSToolbar 在此项目不可用的证据。
- 显示/隐藏全部笔记窗口 `toggleNoteWindows`（`StickyNotesApp.swift:273-283`）**按 title 过滤 `NSApp.windows`**——窗口标题改为派生标题后必须改用注册表（风险 R2）。

### 1.2 编辑器层（App/Sources/Features/Editor/）

- **RichTextView.swift（288 行）**：NSViewRepresentable 包装 `NotePaperTextView`（NSTextView 子类，`intrinsicContentSize` 定制 :275-288）。`textContainerInset = (4, 16)`（:86）是首行呼吸空间的唯一来源；**无 NSScrollView**（裸 NSTextView 嵌入 SwiftUI ScrollView）；`allowsUndo = true`（:70）；模型推送时清空 undo 栈（:123）。Delegate 仅实现 `textDidChange`（:126-132，IME 保护）/`textDidBeginEditing`/`textDidEndEditing`（:134-141）；**无 `textDidChangeSelection`、无 first-responder 管理、无格式 UI、无 `usesFontPanel`**。canonicalDocument 已支持 bold/italic/underline/strikethrough/inlineCode/link 标记往返（FR-053，:147-211），但应用内无任何 UI 能产生这些标记（只能粘贴 RTF 进来）。
- **RichTextBlockView.swift（320 行）**：`ScrollView { VStack }`；**没有标题块**（标题在 NoteControlsView）；块 = 顶部单一 richText 无缝面 + `LazyVStack` 特殊块；内边距 `.padding(.horizontal, 10)` + bottom 10（:188-189）；每块 `BlockContainer` h14/v4。
- **BlockInsertionControl.swift（157 行）**：`+` 菜单（Todo/Code/FileRef/Screenshot，:87-104），macOS 26+ `glassEffect(.regular, in: Circle())`（:116-124）；**触发绑定 `isCursorLineHovered`/`isTextSelected` 从未被置位——控件当前永远隐藏（死代码）**；插入全为 append-only（`sortKey = max+1024`），无"块边界空间插入"。
- **插入入口清单**（UI → 动作）：相机/截图（NoteControlsView.cameraButton → confirmationDialog Region/Window → `host.captureRegion/captureWindow` → `captureScreenshot`）；文件附件（paperclip → NSOpenPanel → `insertFileReferenceBlock`）；Finder 拖放（`NoteWindowContent.onDrop` :535-545 → 同方法）；Todo/Code（菜单 ⇧⌘T/⇧⌘C → NotificationCenter（名字在 `SettingsView.swift:225-231`）→ 协调器观察 :67-87 → 按 `isKeyWindow` 派发 `insertInKeyWindow` :111-129）；**图片插入路径不存在**（`.image` 块只有渲染+动作，无创建路径）；`dragOut`/`embeddedImageData` 为未接线死 API。
- 字号：`Note.textSize`（9–24/1，默认 13）→ `ReadableTheme.textSize` → RichTextView 全文档属性，每 push 重建每个 run；**仅作用于 richText 块**，无逐块/逐选区字号。

### 1.3 模型与命令层

- **NoteWindowHostModel.swift（741 行，@MainActor @Observable）**：`note`（appearance 单一事实源）、`blocks`；`updateAppearance` :78-100（立即持久化 + FTS + sync + widget）；`updateBlocks(_:isStructural:)` :105-119（autosave 500ms 去抖/结构性立即）；`close()` :666（flush + FR-012a 自动删除判定）。全部外观字段经 `repo.update(note, modifyingDeviceId:)` 持久化到 SQLite `note` 表（**无 UserDefaults**）。
- **Note 模型**（Domain/Models.swift:20-124）：`title: String?`、`colorKey`（7 色 + custom）、`customColor: String?`、`transparency: Double`（0.40–1.00/0.05，语义=透明度）、`textSize: Int`、`alwaysOnTop: Bool`（DB 列）、`widgetEligible` 等。
- **MenuCommands.swift（94 行）**：声明式目录（`MenuCommandCatalog`，MenuChecklistTests 校验）；实际 CommandGroup 在 `StickyNotesApp.swift:119-216` 硬编码。现有插入菜单 ⇧⌘T/⇧⌘C 走 NotificationCenter。
- **⌥C/⌥O/⌥T**（颜色/透明度/字号步进）是 `NoteControlsView.swift:173-184` 的三个隐藏按钮——随控件行移除需迁移。

### 1.4 不透明度的真实语义（关键审计）

- `ReadableTheme.background(for:)`（:20-33）：调色板色 `.opacity(note.transparency)`；custom 走 Domain 投影。
- `ReadableTheme.windowBackground(for:)`（:41-56）：**不透明**（custom 色 alpha 1.0）。
- **从不设置 `window.alphaValue`**（全 App 只有截图覆盖层用 `isOpaque = false`）。
- 结论：透明度 = **内容/背景层的 alpha（SwiftUI 层）**，标题栏条带是不透明实色 → 当 transparency < 100% 时标题栏条带与纸面出现可见接缝。新设计（内容延伸至标题栏之下）必须把透明度统一应用到窗口背景色，保持单一内容层语义；**不得**改 `window.alphaValue`（会连镀铬一起淡化）。

## 2. 澄清决策 → 工程映射（源自 spec 2026-08-10 Clarifications）

| 澄清决策 | 工程含义 |
|---|---|
| Q1 最小尺寸：220 pt 强制最小宽 + 140 pt 最小高，一等状态 | `window.contentMinSize = (220, 140)`（替换 300×200）；设计无需在 220 以下降级 |
| Q2 极窄直接可见：截断标题 + 置顶 + 系统溢出；外观/插入仅存溢出 | 语义优先级 → `visibilityPriority`；标题走原生 titlebar 截断；系统 chevron 兜底 |
| Q3 工具栏产品固定，不可自定义；不持久化排列状态 | NSToolbar 用固定 `defaultItemIdentifiers`（不提供 customization palette 扩展行为；`allowsUserCustomization` 保持默认关闭） |
| Q4 插入 = 工具栏下拉菜单（截图/图片/附件/块类型），插入于当前编辑上下文，无则末尾；编辑器内块插入控件保留 | 插入目标解析：富文本光标处（块拆分）→ 特殊块焦点处之后 → 末尾追加；BlockInsertionControl 修复触发 |
| Q5 格式化 = 选中文本或命令触发，锚定编辑器附近的上下文控件组；格式菜单始终可用；失焦消失可接受 | 新增选区观察（textDidChangeSelection）+ 浮动玻璃胶囊行 + Format 菜单；NSTextView 为格式权威 |

## 3. API 证据矩阵（SDK 实测）

来源：`/Applications/Xcode-beta.app/.../MacOSX.sdk`（macOS 27 / Xcode 27A5228h）。部署目标维持 **macOS 26**（AGENTS.md 强制），macOS 27 为视觉主目标。

| API | 框架/位置 | 实测可用性 | 用途 | 必需/可选 | 回退 |
|---|---|---|---|---|---|
| `NSToolbar` / `window.toolbar` | AppKit | 10.x（`NSWindow.h:679`） | 原生工具栏 | 必需 | — |
| `NSToolbarDelegate` `itemForItemIdentifier(_:willBeInsertedIntoToolbar:)` | AppKit | 10.x（`NSToolbar.h:206`） | 项构造 | 必需 | — |
| `NSToolbarItem.visibilityPriority`（Standard=0/Low=−1000/High=1000/User=2000） | AppKit | 10.10+（`NSToolbarItem.h:35-39`）；头注释：最高优先级最后进溢出；>Standard 且 <User 建议常显（:192-194） | 置顶常显语义 | 必需 | 系统自动 |
| `NSToolbarItem.menuFormRepresentation` | AppKit | 10.0+（`NSToolbarItem.h:92`） | 溢出/菜单形态（置顶状态项、插入菜单、更多菜单） | 必需 | 系统 |
| `NSToolbarItem.Style`、`backgroundTintColor`、`badge` | AppKit | macOS 26+（`NSToolbarItem.h:25,142,200`） | 可选视觉增强 | 可选（不采用，避免 API 清单式使用） | — |
| `NSWindow.toolbarStyle`（Unified/UnifiedCompact） | AppKit | 11.0+（`NSWindow.h:312`） | 统一标题栏形态 | 可选（Automatic 即可） | 系统 |
| `NSWindow.titleVisibility` / `.fullSizeContentView` | AppKit | 10.10 / 10.10 | 标题显示 + 内容延伸至标题栏下 | 必需 | — |
| `NSButton.BezelStyle.glass` | AppKit | **macOS 26+**（`NSButtonCell.h:67`，值 16） | 工具栏按钮原生玻璃 | 可选（26+ guard） | `.toolbar`（10.x） |
| `NSButton.BezelStyle.toolbar` | AppKit | 10.x（值 11） | 工具栏按钮 | 必需 | — |
| SwiftUI `glassEffect(_:in:)` | SwiftUICore（SwiftUI 再导出） | **macOS 26+** | 上下文格式化浮动面（唯一自定义玻璃） | 可选（26+ guard） | 普通按钮/材质 |
| `Glass`（.regular/.clear/.identity、`tint(_:)`、`interactive(_:)`） | SwiftUICore | **macOS 26+**（swiftinterface 6880-6897） | 同上 | 可选 | — |
| `glassEffectID(_:in:)` / `glassEffectUnion(id:namespace:)` / `glassEffectTransition(_:)` / `GlassEffectContainer` | SwiftUICore | macOS 26+ | 浮动面分组/过渡（成组语义，spec FR-022） | 可选 | — |
| `EnvironmentValues.appearsActive` | SwiftUICore | macOS 10.15+ | 激活态呈现（如需要） | 可选（默认系统处理） | — |
| `accessibilityReduceTransparency/ReduceMotion/ShowBorders` | SwiftUICore | 10.15+ | 无障碍适配断言/呈现 | 可选 | 系统 |
| 同心圆角（`concentricCornerRadii(in:)` 等） | SwiftUICore | macOS 26+ | — | **不采用**（本特性无靠近窗口角的自定义浮动面） | — |
| Observation `withObservationTracking` / `observe(_:options:changeHandler:)` | Observation | macOS 14+（新 options 重载 macOS 27） | AppKit 侧观察 host | 必需 | — |
| `NSPopover` + `NSHostingController` | AppKit/SwiftUI | 10.10+ | 外观面板 | 必需 | — |

### 3.1 明确拒绝（Anti-checklist）

- **`NSGlassEffectView` / `NSGlassEffectContainerView`**：本特性无 AppKit 自定义玻璃面（工具栏/按钮/菜单/popover 全部系统提供）→ 不用。
- **`Glass.interactive`**：上下文格式化行使用标准按钮（系统自带悬停/按压响应）；无需自定义拖拽/scrubbing 交互 → 不用。自定义玻璃面=一个被动容器 + 标准按钮。
- **同心圆角 API**：唯一自定义浮动面（格式化行）不靠近窗口角 → 显式判定"本特性不需要"。
- **`NSToolbarItem.Style`/`badge`**：无产品需求 → 不用。

## 3.2 Spike 结论（T011，2026-08-10 macOS 27 实测）

标准 `NSWindow` + `.fullSizeContentView` + `titlebarAppearsTransparent` + `NSToolbar` 组合验证（R1 缓解）：

1. **组合可用**：`styleMask` 含 `.fullSizeContentView` 时内容层延伸至标题栏之下；红绿灯保持标准（生命周期套件 `snapshotNoteWindowKeepsStandardTrafficLightChrome` 断言 through `.titled/.closable/.resizable`）；`window.title` 经 `titleVisibility = .visible` 正常渲染；工具栏项/溢出/优先级全部系统行为。
2. **发现 min-size 传播陷阱**：NSHostingView 会把 SwiftUI 内在最小尺寸（ScrollView → 约 0×52）在首次布局后传播覆盖 `contentMinSize`（探针实测：orderFront 后 contentMinSize 变为 (0.0, 52.0)）。缓解：`open()` 中 orderFront 后同步 `layoutSubtreeIfNeeded()` 再重设 `contentMinSize = (220,140)`，并在 `windowDidResize` 复检（T012 已落地；T004 断言锁死）。
3. **工具栏挂载顺序**：min size 必须在 `window.toolbar = …` 挂载之后设置（AppKit 挂载瞬间会用工具栏默认值覆盖一次）。
4. 本场景为标准 NSWindow，与 Library spike 失败（MenuBarExtra 私有窗口类）无关——组合可行性确认。

## 4. 关键技术决策
- **D1 工具栏宿主**：新建 `NoteToolbarController`（@MainActor，App 层，每窗口一个），由 `NoteWindowCoordinator` 创建/持有/释放（镜像 `windowDelegates` 字典模式）。理由：协调器已 657 行且职责杂；NSToolbar 生命周期与窗口强绑定；controller 与 delegate 同生共死。**不引入**自定义 NSWindow 子类、不新建窗口框架。
- **D2 标题**：`window.title` = 派生标题（手动标题 → 内容首行 → 本地化兜底"无标题笔记"），`titleVisibility = .visible`；标题编辑移动到内容顶部新标题输入框（替换 NoteControlsView.titleField）；同步方向 host→window（协调器方法，NoteWindowContent `.onChange` 触发）。
- **D3 透明度统一**：`ReadableTheme.windowBackground` 增加 `note.transparency` 应用，与纸面一致；不碰 `alphaValue`。
- **D4 插入目标语义**（FR-010 的工程解释）："当前编辑器插入点"= ①富文本块内光标 → 按光标偏移拆分 richText 块（保留 run 属性），新块插中间；②特殊块有焦点 → 插该块之后；③无活动上下文 → 末尾追加。块拆分 = 纯函数（可单测）。
- **D5 格式权威**：NSTextView textStorage/typingAttributes 是唯一权威；SwiftUI 只做呈现与触发；标记经既有 canonicalDocument 往返（FR-053 已支持）。
- **D6 生命周期修复**：`windowWillClose` 增加 `NoteWindowBridge.unregister` + 释放 toolbar controller（与 ⌘W 路径对齐）；修复复活死 host 缺陷。`toggleNoteWindows` 改用注册表过滤。
- **D7 死代码处理**：BlockInsertionControl 修复触发（hover/selection 接线）使其成为真正的上下文插入路径（spec FR-010"编辑器内块插入控件保留"）；`dragOut`/`embeddedImageData` 死 API 不动（非本特性范围）。

## 5. 备选方案与否决

| 方案 | 否决理由 |
|---|---|
| SwiftUI `.toolbar` 替代 AppKit NSToolbar | 失去 `visibilityPriority`/`menuFormRepresentation`/原生溢出/自定义面板等核心能力；spec 明确"不要为原生能力强塞 SwiftUI" |
| 自定义 NSWindow 子类做镀铬 | 反模式清单明令禁止；系统已提供全部所需 |
| 保留 NoteControlsView + 叠加 NSToolbar | 反模式清单明令禁止（双镀铬） |
| NSGlassEffectView 包裹工具栏 | 系统工具栏已是玻璃；重复包裹属"过度玻璃" |
| 手写断点隐藏工具栏项 | 系统溢出按优先级接管；仅内容内边距保留 2 态语义间距（NSToolbar 无法表达，明确正当理由） |
| 每宽度多套工具栏配置 | 单一配置 + 系统溢出即达全部目标宽度 |
| 逐选区字号 | 规范模型（RichTextRun）无 per-run 字号；001 FR-043a 语义=整笔记字号 → 上下文字号控件调整 `note.textSize`（整笔记），选区级别仅标记格式 |

## 6. 风险摘要（详见 plan.md §10）

R1 fullSizeContentView+透明标题栏+工具栏组合未在本项目验证（无 NSToolbar 先例）→ Phase 2 前置 spike 任务。
R2 `toggleNoteWindows` 按 title 过滤 → 改注册表。
R3 富文本块光标拆分是唯一编辑器手术 → 纯函数 + 单测隔离，Phase 4 独立交付。
R4 标题每击键派生 → 仅字符串级计算，按 blocks 变化节流，无性能风险。
R5 菜单双路由（NotificationCenter + 工具栏直调）→ 保持"单一操作，双路由"并文档化；不改既有菜单路径以免回归。
