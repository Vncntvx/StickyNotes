# Implementation Plan: 独立笔记窗口原生镀铬与自适应重设计（Native Toolbar + Liquid Glass）

**Branch**: `004-note-window-native-redesign` | **Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

**Input**: Feature specification from `/specs/004-note-window-native-redesign/spec.md`（含 2026-08-10 澄清会话 Q1–Q5 决策）

## Summary

以标准 macOS 标题栏 + 系统窗口工具栏（AppKit NSToolbar）取代 `NoteControlsView` 常驻自定义控件行，使笔记窗口在 220–2000+ pt 全宽度下保持同一连贯原生观感。核心内容：新 `NoteToolbarController`（每窗口一个，AppKit 侧）承载置顶/外观/插入/更多四项 + 原生标题栏标题；内容层延伸到标题栏之下（`.fullSizeContentView`），笔记颜色/透明度构成统一内容层，系统玻璃浮于其上；上下文格式化（选区观察 + 浮动玻璃控件组 + Format 菜单）与统一插入工作流（下拉菜单 + 光标处块拆分）；生命周期缺陷修复（关闭时反注册 + 复活修复）；既有编辑器/块/持久化/桥接层全部保留。

## Technical Context

**Language/Version**: Swift 6（Swift 6 语言模式，严格并发）| 工具链：本地 Xcode 27 beta（27A5228h，Swift 6.4，macOS 27 SDK）；CI 目标 Xcode 26.x / Swift 6.3 / macOS 26 SDK

**Primary Dependencies**: AppKit（NSToolbar/NSToolbarItem/NSWindow/NSPopover/NSButton）、SwiftUI + SwiftUICore（glassEffect/Glass/Observation）、SystemBridge（NoteWindowBridge/WindowLevelBridge 沿用）、GRDB（Persistence 层不动）

**Storage**: 无 schema 变更；`note` 表（外观字段）+ `windowState` 表（帧）既有语义不变；不新增持久化

**Testing**: Swift Testing（`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` 前缀，见 AGENTS.md）；AppTests 单测/集成 + 手动/UI 验证（quickstart.md）；CI 保持 Xcode 26 兼容

**Target Platform**: macOS 26+（部署最低 macOS 26，AGENTS.md 强制；macOS 27 视觉主目标）

**Project Type**: desktop-app（macOS，混合 AppKit + SwiftUI 模块化单体）

**Performance Goals**: 001 目标不回归（新窗口呈现 ≤200 ms、击键→字形 <16 ms、空闲无轮询）；缩放由系统布局负责，无逐帧手动测量；标题派生按 blocks 变化节流（字符串级计算）

**Constraints**: 不引入自定义 NSWindow 子类；不替换富文本编辑器；macOS 26 API 表面内保持可编译（CI 为 26 SDK）；27 专属 API 一律 `if #available` 守卫；不持久化工具栏排列/临时 UI 状态

**Scale/Scope**: 每窗口一个 toolbar controller + 一个 selection bridge；新增 ~4 个 App 层文件；编辑器仅 3 处小改（选区观察、格式入口、块拆分纯函数）

## Constitution Check

*GATE：规划后复检。以下逐原则过检：*

- **XII（测试先行）**：Phase 1 先落失败测试（红灯 pin 已存在：`NoteWindowLifecycleTests:114` fullSizeContentView；新增 minSize 220 / 关闭反注册 / 标题派生 / 插入目标 / 格式往返测试均先行编写并先红后绿）。✅
- **XIV（规格完备性）**：本计划每阶段映射到 spec FR（见 §8 各阶段 FR 引用）；数据/隐私/无障碍/性能/失败恢复各节已覆盖。✅
- **VII（隐私与最小权限）**：无新增权限请求；截图/摄像头走既有流程（入口聚合）；不采集遥测。✅
- **VI（最小权限）**：无障碍权限语义不变；本特性不触达。✅
- **X（可达性）**：置顶/插入/格式化均有菜单命令路径；⌥C/⌥O/⌥T 保留；VoiceOver/键盘走查列入测试。✅
- **III/IV（本地优先/离线）**：所有状态仍本地 DB；无网络依赖。✅
- **XI（无重复状态）**：单一事实源映射见 §3.3（host.note / NSTextView / WindowLevelBridge 均不引入副本）。✅

无违反需登记 Complexity Tracking。

## Project Structure

### Documentation (this feature)

```text
specs/004-note-window-native-redesign/
├── plan.md              # 本文件
├── research.md          # Phase 0：SDK 实测 API 证据 + 代码勘查
├── data-model.md        # Phase 1：状态所有权模型
├── quickstart.md        # Phase 1：验证指南
├── contracts/README.md  # Phase 1：内部契约
└── tasks.md             # Phase 2 输出（/speckit.tasks）
```

### Source Code (repository root)

```text
App/Sources/Features/NoteWindow/
├── NoteWindowCoordinator.swift      # 改：镀铬、标题、内容结构、生命周期、工具栏接线
├── NoteToolbarController.swift      # 新：NSToolbar 生命周期/项/动作/状态同步/弹出控件/菜单
├── AppearancePanelView.swift        # 新：外观面板（调色板+透明度+重置，SwiftUI）
├── NoteWindowHostModel.swift        # 改：插入目标 API + insertImageBlock + 标题派生访问
├── ReadableTheme.swift              # 改：windowBackground 应用透明度
├── NoteControlsView.swift           # 删（功能迁入工具栏/菜单/上下文/内容标题框）
├── NoteExportImport.swift           # 不动
└── AccessibilityAdaptations.swift   # 不动
App/Sources/Features/Editor/
├── RichTextView.swift               # 改：选区观察/格式入口/选区矩形
├── RichTextBlockView.swift          # 改：顶部标题框接线、顶部内边距、上下文行挂载
├── EditorSelectionBridge.swift      # 新：@Observable 选区/焦点桥（AppKit→SwiftUI）
├── BlockInsertionControl.swift      # 改：修复死触发（hover/selection 接线）
└── （其余块视图不动）
App/Sources/App/
├── StickyNotesApp.swift             # 改：Format 菜单、View 菜单置顶、toggleNoteWindows 改注册表
└── MenuCommands.swift               # 改：目录新增条目
AppTests/
├── NoteWindowLifecycleTests.swift   # 改：minSize 220、关闭反注册、fullSizeContentView 转绿
├── NoteToolbarStateTests.swift      # 新
├── TitleDerivationTests.swift       # 新
├── InsertionTargetingTests.swift    # 新
├── FormattingRoundTripTests.swift   # 新
├── AppearancePanelStateTests.swift  # 新
└── MenuChecklistTests.swift         # 改：新菜单条目
```

**Structure Decision**: 沿用现有 feature-area 目录布局；不新建框架/模块。AppKit 侧新类归 `Features/NoteWindow/`（与协调器同域），SwiftUI 面板/桥归同一 area；不触碰 StickyCore（SystemBridge/Persistence 零改动）。

## 1. 当前实现勘查结论（摘要）

详见 [research.md](./research.md) §1。要点：

1. `NoteWindowContent` 与 `NoteWindowDelegate` 都定义在 `NoteWindowCoordinator.swift`（657 行）内；`NoteControlsView` 是唯一常驻控件行（ViewThatFits 三档），含标题/颜色/透明度/字号/置顶/相机/附件/关闭。
2. 窗口：`contentMinSize 300×200`、`titleVisibility = .hidden`、`titlebarAppearsTransparent = true`、无 `.fullSizeContentView`（对应已提交红灯测试）。
3. **既有缺陷**：红绿灯关闭不反注册 `NoteWindowBridge` → 复活死 host 窗口（spec 成功标准 15 的修复项）。
4. 透明度语义 = 内容层 alpha（SwiftUI `ReadableTheme.background`），标题栏条带为不透明实色 → transparency<100% 时有可见接缝。
5. 编辑器：无选区观察、无格式 UI、无 first-responder 管理；插入全 append-only；`BlockInsertionControl` 触发从未接线（当前恒隐藏）；`.image` 块无创建路径。
6. 置顶/外观/持久化路径单一权威：`host.updateAppearance` → `repo.update`（立即）；`WindowLevelBridge` 是窗口行为权威。
7. 应用零 NSToolbar 先例；但标准 NSWindow + NSToolbar 组合的可行性已由 SDK API 与系统约定背书（Library spike 失败源于 MenuBarExtra 私有窗口类，与本场景无关）。

## 2. 目标架构

### 2.1 AppKit 责任（窗口系统天然归属）

- `NSWindow`：创建、styleMask（含 `.fullSizeContentView`）、minSize（220×140）、`title`（派生）、`toolbar`（挂载 `NSToolbar`）、透明度统一窗口背景、`titlebarAppearsTransparent` 保持。
- `NoteToolbarController`（新）：NSToolbar 创建/配置/委托、项构造与优先级、动作路由、host 状态观察（Observation）、外观 NSPopover、插入/更多 NSMenu、置顶状态同步。
- `NoteWindowDelegate`：生命周期/帧持久化（沿用）+ 关闭反注册修复。
- 系统行为（交给 OS）：溢出 chevron、项显隐、激活/失活、工具栏玻璃外观、菜单/弹出控件材质。

### 2.2 SwiftUI 责任

- `NoteWindowContent`：内容结构（标题框 + 编辑器 + 上下文菜单 + 上下文格式化行挂载 + ⌥C/⌥O/⌥T 迁移 overlay）。
- `AppearancePanelView`（新）：调色板/透明度/重置（NSPopover 内）。
- 编辑器（RichTextBlockView/RichTextView/块视图）：保持。
- `EditorSelectionBridge`（新，@Observable）：选区/焦点桥。

### 2.3 状态所有权（单一事实源，防重复状态）

| 状态 | 单一事实源 | 观察/同步方向 |
|---|---|---|
| 笔记标题（DB） | `Note.title`（host.note） | 编辑→`updateAppearance`→DB；协调器派生 `window.title`（host→window 单向） |
| 颜色/透明度/字号/置顶/标签 | `Note` 外观字段（DB） | 工具栏/面板→`updateAppearance`→DB；控制器 `observe` host 刷新项状态 |
| 窗口置顶行为 | `WindowLevelBridge` + `NoteWindowBridge.applyCollectionBehavior` | `coordinator.updateAlwaysOnTop` 唯一入口 |
| 文本/标记/选区 | NSTextView（textStorage/typingAttributes/selectedRange） | SwiftUI 只读快照（selection bridge），写操作经 NSTextView 直改 |
| 块/内容 | `NoteWindowHostModel.blocks` + autosave | 既有 updateBlocks 路径不变 |
| 窗口帧 | `SQLiteWindowStateRepository`（windowState 表） | NoteWindowDelegate 既有 |

**观察机制**：`NoteToolbarController` 用 Observation（`withObservationTracking` 循环或 `observe`，macOS 14+）订阅 `host.note` 的 `alwaysOnTop`/外观字段变化 → 刷新项状态/面板；**不引入 NotificationCenter 新用法**（既有菜单 NotificationCenter 路径保留原样）。

**生命周期与 retain 链**（无环）：

```
NoteWindowCoordinator ──retains──> NoteToolbarController ──weak──> NSWindow.delegate(NoteWindowDelegate)
        │   │                           │  │  │  └─ weak ─ NSWindow
        │   └── hosts[noteId] ─────────┘  │  └─ weak ─ NoteWindowHostModel 引用（经协调器传递）
        └── windowDelegates[noteId]       └─ NSPopover（popover.contentViewController 持有面板）
```

- `NoteToolbarController` 由协调器 `toolbars[noteId]` 强持有；释放与 `releaseWindowDelegate` 同步（关闭路径统一）。
- 控制器不持有 NSWindow 强引用（经协调器方法操作窗口）；popover 由控制器持有，关闭时 close。
- `NoteWindowHostModel` 被 `hosts` 持有；控制器只经协调器/闭包访问，不反向持有协调器循环（闭包捕获协调器弱引用或经方法调用）。

### 2.4 生命周期（open → close）

```
open(noteId:)
 → focusExisting?（已注册→激活返回；修复后红绿灯关闭即反注册，此分支仅剩未关干净场景）
 → repo.fetch(note) → NoteWindowHostModel（hosts[noteId]）
 → NSWindow 创建（styleMask+.fullSizeContentView, minSize 220×140, title=派生, backgroundColor=透明度统一色）
 → NoteToolbarController 创建（toolbars[noteId]）→ window.toolbar = controller.toolbar → 初始状态同步
 → NoteWindowContent(host) → NSHostingView → contentView
 → restoredFrame → setFrame
 → NoteWindowDelegate 挂载（windowDelegates[noteId]）
 → NoteWindowBridge.register + applyCollectionBehavior + WindowLevelBridge.apply
 → makeKeyAndOrderFront
close（红绿灯/⌘W/菜单）
 → windowWillClose：saveFrame → 反注册（NoteWindowBridge.unregister）→ 释放 toolbar 控制器 + delegate + host（close() flush + FR-012a）→ 任务结束
```

## 3. 原生工具栏设计

### 3.1 结构

- `NSToolbar(identifier: "note.window.toolbar")`；`window.toolbar = toolbar`；`toolbarStyle = .automatic`（系统决定统一形态）。
- 固定项（Q3 决策：不开放用户定制；不提供 customization palette 扩展）：`defaultItemIdentifiers = [pin, appearance, insert, more]`；`allowedItemIdentifiers` 同集。
- 委托：`itemForItemIdentifier(_:willBeInsertedIntoToolbar:)` 单点构造 + 缓存（`toolbarItems` 字典，窗口生命周期内不重建对象图——性能要求）。

### 3.2 工具栏项表（FR-006/FR-015a/FR-015b 的显式映射）

| 项 | 用途 | 原生表示 | 常驻/上下文 | 可见性优先级 | 溢出形态 | 状态源 | 动作路径 | 键盘/菜单等价 | API 依赖 |
|---|---|---|---|---|---|---|---|---|---|
| **Pin** | 置顶开关（FR-007/026） | NSToolbarItem（view = NSButton bezelStyle `.toolbar`/`.glass`，`setButtonType(.toggle)`，图标 pin/pin.fill 随 state 切换） | 常驻高优先级 | `.high`（头注释背书：>Standard 且 <User 建议常显，最后进溢出） | `menuFormRepresentation` = NSMenuItem（toggle，state 随动） | `host.note.alwaysOnTop`（DB） | `coordinator.updateAlwaysOnTop`（既有唯一入口） | 新 View 菜单 "Always on Top"（toggle，无快捷键）；`accessibilityValue` 开/关 + tooltip | `.glass` 需 macOS 26 guard |
| **Appearance** | 颜色+透明度整合（FR-008/009） | NSToolbarItem（view = NSButton `.toolbar`/`.glass`，paintpalette 图标）→ 点击弹出 NSPopover（NSHostingController → `AppearancePanelView`） | 常驻中优先级 | `.standard` | `menuFormRepresentation` = 外观子菜单（颜色 7 项 + 透明度 13 步 + 重置） | `host.note`（colorKey/customColor/transparency） | 面板改动→`host.updateAppearance`+`coordinator.updateNotePaper`（即时预览，FR-008） | 既有 ⌥C/⌥O 步进保留；外观子菜单（从 NoteControlsView 上下文菜单迁移） | NSPopover 10.10+ |
| **Insert** | 统一插入入口（FR-010/Q4） | NSToolbarItem（view = NSButton `.toolbar`/`.glass`，plus 图标，pullsDown）→ NSMenu：截图子菜单（区域/窗口）、插入文件引用…、插入图片…（新）、待办（⇧⌘T）、代码块（⇧⌘C） | 常驻中优先级 | `.standard` | 同上 menuFormRepresentation 菜单 | 无（动作型） | 菜单项→协调器→`host` 既有插入方法（目标解析见 §4.3） | 既有 ⇧⌘T/⇧⌘C + 既有 File/Edit 菜单 Insert 组 | — |
| **More** | 低频动作（FR-011） | NSToolbarItem（view = NSButton `.toolbar`/`.glass`，ellipsis.circle）→ NSMenu：复制笔记、复制为 Markdown、导出 JSON…、移入废纸篓（⌘⌫）、分隔线、允许小组件（toggle）、设为小组件笔记/移除 | 常驻 | `.standard` | 同上（窄宽度时可自身溢出进 chevron） | 动作型 + `widgetEligible` | 既有闭包：duplicate/copy/export/moveToTrash/widget 选择（从 NoteControlsView 上下文菜单迁移） | 既有菜单：⌘⌫、上下文菜单（内容区 .contextMenu 保留） | — |
| **标题** | 窗口身份（FR-003/Q2） | 原生 `window.title`（非工具栏项） | 常驻（titlebar 区） | 系统标题截断（不进溢出） | 系统截断 | `Note.title` 或内容首行 | 协调器 `updateWindowTitle(noteId:)`（host→window） | 无 | 10.10 titleVisibility |

**禁止项**：无 title 工具栏项、无数字/文本项、无自定义间距项（弹性空间由系统工具栏布局提供）。

### 3.3 溢出行为

- 系统 chevron 自动承载溢出项；顺序由 `visibilityPriority` + 系统布局决定：Pin（.high）最后溢出（Q2：220–240 pt 直接可见 = 标题截断 + Pin + chevron）；Appearance/Insert/More（.standard）先进溢出。
- 溢出菜单中每个项使用 `menuFormRepresentation`（Pin 为带 state 的 toggle；其余与主菜单相同 NSMenuItem）——**同一动作单一实现，多形态呈现**（工具栏按钮/溢出项/应用菜单/上下文菜单指向同一操作）。
- 不使用任何自定义"假溢出"。

### 3.4 标题行为（FR-003/Q1/Q2）

- 派生规则（纯函数，可单测）：`title ?? 内容首行（去空白） ?? 本地化"无标题笔记"`。首行派生复用 001 FR-020/021 卡片摘要的既有提取逻辑（实施时定位 `CardProjection` 摘要辅助并抽取共享）。
- 同步方向 host→window：`NoteWindowContent.onChange(of: host.note?.title)` 与 `onChange(of: host.blocks)`（首行派生情形）→ `coordinator.updateWindowTitle(noteId:)`（字符串级计算，无性能风险）；打开时设初值。
- 标题编辑：内容顶部新标题输入框（替换 NoteControlsView.titleField，Q：编辑留在内容层）；空→nil 语义保留。
- 截断：系统 titlebar 规则（尾截断）；不占工具栏项空间；极窄宽度由系统决定最小可视长度（Q2 已定：允许截断、不得推出控件）。
- 与编辑器坐标系统一：`.fullSizeContentView` 使内容延伸至标题栏之下，标题栏/编辑器不再有坐标系分叉观感（spec FR-017 禁止项）。

### 3.5 命令集成（FR-011/FR-029，003 FR-072 语义）

- 新增菜单（`StickyNotesApp.swift` Commands + `MenuCommands.swift` 目录同步）：
  - View：Always on Top（toggle，作用于 key 笔记窗口，复用 `updateAlwaysOnTop`）；
  - Format：粗体 ⌘B / 斜体 ⌘I / 下划线 ⌘U / 删除线（无快捷键）/ 代码样式（无快捷键）/ 文本大小（菜单 9–24 全列表，⌥T 步进保留）——作用于 key 窗口的 active NSTextView；
  - Insert 组保持既有（⇧⌘T/⇧⌘C + 文件引用/截图），新增"插入图片…"。
- 双路由文档化：应用菜单经既有 NotificationCenter → 协调器 keyHost 派发；工具栏经控制器直调 host——**同一 host 操作**（`insertTodoBlock`/`insertCodeBlock`/`insertFileReferenceBlock`/`captureScreenshot`/新增 `insertImageBlock`），无第二套插入模型（spec FR-010"避免两套 Insert 系统"）。
- `toggleNoteWindows` 改为 `NoteWindowBridge.allRegistrations()` 过滤（修复标题过滤依赖）。

## 4. 功能交互计划

### 4.1 Pin（FR-007/026 + Q3 持久化范围）

- 读取：`host.note.alwaysOnTop`（DB 权威，001 FR-034 语义）；控制器 `observe` 刷新按钮 state/图标/溢出菜单 state。
- 更新：按钮 toggle → `coordinator.updateAlwaysOnTop(noteId:)`（内部：`WindowLevelBridge.apply` + `applyCollectionBehavior` + pin 时 `orderFrontRegardless`；持久化在 `host.updateAppearance` 既有路径中完成——控制器先调 host 再调协调器，与现 NoteControlsView 行为逐字一致）。
- 布局：按钮视图固定尺寸，状态变化仅换图标/state，**不改变几何**（FR-007 禁止布局位移）。
- 溢出/菜单/菜单栏：三处均指向同一 `updateAlwaysOnTop`；失活窗口沿用系统工具栏渲染（spec 禁止自定义失活态）。
- 持久化：DB（既有），跨关闭/重启自然成立；多窗口独立。

### 4.2 外观工作流（FR-008/009 + Q3）

- 工具栏表示：Appearance 项（paintpalette）；点击 → NSPopover（非激活式锚定，标准行为），内容 `AppearancePanelView`（SwiftUI）：
  - 颜色：7 键调色板（`NotePaletteKey`，含 custom——peach 走既有 `paletteStorage` 映射，001 FR-032 语义：**既有颜色值逐字保留**）；选中态 = 勾选 + 名称 + 色块（不只靠颜色，001 FR-044）；
  - 透明度：Slider 0.40–1.00 步 0.05（13 步，001 FR-041a），旁标"NN%"完整数值（**任何宽度不截断**，FR-009）；无障碍 value 播报；
  - 重置："恢复默认"按钮（默认调色板 + transparency 1.0，FR-008"恢复合理默认"）；
  - 即时生效：每次改动 → `host.updateAppearance` + `updateNotePaper`（无确认按钮）；
  - 关闭：popover 标准消失（点外/ESC）；不持久化打开状态。
- 不透明度语义（research §1.4）：透明度 = 内容层 alpha；本特性把 `ReadableTheme.windowBackground` 也应用 `note.transparency`，消除标题栏条带接缝；**不触碰 `window.alphaValue`**（否则连原生镀铬一起淡化，违反 FR-021 层级）；对比度校验沿用 `NoteAppearance.projecting`（custom+opacity 对合成背景）。

### 4.3 插入工作流（FR-010 + Q4）

- 入口：工具栏 Insert 下拉菜单（§3.2）；编辑器内 `BlockInsertionControl` 修复触发（hover/选区接线）成为空间上下文路径——两者并存、动作同源。
- 目标解析（纯函数 `resolveInsertionTarget`，可单测）：
  1. 富文本块有光标/选区 → 光标偏移处拆分 richText 块为两段（保留 run 属性），新块（todo/code/fileRef/image/screenshot）以中间 sortKey 插入；
  2. 特殊块（todo 输入框等）有焦点 → 插于该块之后；
  3. 无活动插入点（编辑器非第一响应者/窗口刚打开）→ 末尾追加（`max+1024`，既有行为）。
- 动作清单：截图（区域/窗口，既有 `captureScreenshot` 流程含权限确认）；文件引用（既有 `pickAndInsertFileReference`）；**插入图片…（新）**：NSOpenPanel（图片类型）→ `host.insertImageBlock`（新方法：asset 导入复用截图资产管线 → `.image` 块，镜像 `captureScreenshot` :408-436 模式）；待办/代码（既有 host 方法）。
- 异步完成：截图/文件选择为异步流程 → 目标在发起时解析并捕获（插入上下文快照），完成后落位；窗口关闭/内容变化时安全降级为末尾追加（失败恢复语义）。
- 不做独立插入模型：全部复用 `host` 既有/新增方法。

### 4.4 上下文格式化（FR-012/013 + Q5）

- 触发：`EditorSelectionBridge`（新 @Observable）经 `RichTextView` 新增 `textDidChangeSelection` 发布：有选区/无选区/选区矩形（layoutManager 换算窗口坐标）/第一响应者态；格式菜单/快捷键触发同源。
- 呈现：选区存在时，编辑器顶部/选区上方显示浮动玻璃胶囊行（SwiftUI：B/I/U/删除线/代码/字号菜单，标准按钮 + 容器 `glassEffect(.regular)` + `glassEffectID/union` 成组，macOS 26 guard）；无选区/失焦消失（Q5：可接受，Format 菜单为稳定入口）。
- 焦点纪律：胶囊行按钮不成为 first responder（`refusesFirstResponder`/手势触发），不打断编辑焦点。
- 动作路由：全部直改 NSTextView（textStorage/typingAttributes）——**NSTextView 是格式权威，SwiftUI 无格式状态副本**；标记经既有 canonicalDocument 往返（bold/italic/underline/strikethrough/inlineCode 已支持，FR-053）。混合格式：无选区→作用于 typingAttributes；有选区→按选区首个字符属性显示态。
- 字号：上下文菜单调整 `note.textSize`（整笔记，001 FR-043a 语义——规范模型无 per-run 字号，research §5 已记录此边界）。

## 5. Liquid Glass 策略

### 5.1 Category A — 系统提供（零自定义代码）

原生标题栏、NSToolbar、工具栏按钮（`.toolbar`/`.glass` 外观）、菜单、溢出 chevron、NSPopover、标准控件：全部由 macOS 27 系统提供 Liquid Glass 外观；macOS 26 系统提供既有玻璃外观。**不得**用 NSGlassEffectView 包裹任何标准控件（research §3.1 明确拒绝）。

### 5.2 Category B — 自定义玻璃（仅一处）

上下文格式化浮动行（§4.4）：容器 `glassEffect(.regular)` + `GlassEffectContainer`/`glassEffectID` 成组（spec FR-022 成组语义）——这是唯一"浮于内容之上且标准工具栏无法表达"的定制面；BlockInsertionControl 既有 `glassEffect(.regular, in: Circle())` 保持。`Glass.interactive` 不采用（标准按钮已具备系统交互响应；无 scrubbing 需求）。

### 5.3 macOS 27 细化

- `NSButton.BezelStyle.glass`（macOS 26+）用于工具栏按钮（guard 内）；26 以下用 `.toolbar`（但部署目标即 26）。
- 激活/失活、Reduce Transparency、深色模式：全部交给系统（spec FR-029/FR-035；不写自定义呈现逻辑）。

### 5.4 无障碍行为

- 图标控件：`accessibilityLabel` + `accessibilityValue`（置顶开/关）+ tooltip（`toolTip`/`help`）。
- 不透明度滑块数值播报；颜色按钮名称+选中态；溢出菜单项与可见项同一 accessibility 语义。
- Reduce Transparency / Increase Contrast / Reduce Motion：系统处理；自定义玻璃面在系统降级时退化为普通控件呈现（glassEffect 由系统自动处理降级；不手工复刻）。

## 6. 兼容矩阵

| 能力 | macOS 27（主目标） | macOS 26（最低部署） | 更旧（不支持） | 回退 |
|---|---|---|---|---|
| NSToolbar/溢出/优先级/menuFormRepresentation | 原生 | 原生 | — | — |
| 工具栏按钮玻璃（`BezelStyle.glass`） | 原生 Liquid Glass | 原生玻璃（26 起） | — | `.toolbar`（26 已含，防御性 guard） |
| 上下文格式化行 `glassEffect` | 原生 | 原生（26 起） | — | 普通按钮材质（guard 内） |
| 窗口/标题栏/标题/全尺寸内容 | 原生 | 原生 | — | — |
| 内容/标题/置顶/插入/格式化功能 | 全量 | 全量 | — | 功能不因视觉能力缺失而缩减 |

- 原则（spec FR-035 + 用户输入）：功能处处保留；新视觉能力增量附加；27 专属 API 用 `#available` 守卫；**不**按 OS 分叉整套窗口实现（仅围绕真正不可用的能力做窄守卫）；**不**手写仿制视觉效果。

## 7. 文件级变更映射

| 文件 | 当前职责 | 变更后职责 | 变更性质 | 受影响依赖 |
|---|---|---|---|---|
| `NoteWindowCoordinator.swift` | 窗口创建/内容根视图/委托/菜单派发 | +fullSizeContentView、minSize(220,140)、标题派生与同步入口、透明度统一背景、工具栏接线、关闭反注册修复、移除 NoteControlsView（内容顶部标题框替代）、上下文菜单迁移 | 大改（同文件内结构性重组） | NoteWindowHostModel、NoteWindowBridge、WindowLevelBridge、NoteToolbarController（新） |
| `NoteToolbarController.swift`（新） | — | NSToolbar 全生命周期、项构造/优先级/状态同步、外观 popover、插入/更多菜单、标题更新触发 | 新文件 | 协调器、host（经闭包）、ReadableTheme |
| `AppearancePanelView.swift`（新） | — | 调色板/透明度/重置/即时预览（SwiftUI） | 新文件 | host、NotePalette |
| `NoteWindowHostModel.swift` | 状态与持久化动作 | +插入目标解析调用、+`insertImageBlock`（图片资产导入，镜像截图管线）、+标题派生访问（首行提取） | 小改 | Domain、AssetStore |
| `ReadableTheme.swift` | 纸面/窗口色 | windowBackground 应用透明度 | 小改 | NoteAppearance |
| `NoteControlsView.swift` | 控件行 | **删除**（功能已迁：标题→内容顶部框；颜色/透明度/字号→外观面板+菜单；置顶/相机/附件/关闭→工具栏/菜单；上下文菜单→内容区+More；⌥C/⌥O/⌥T→内容 overlay） | 删除 | 全部由上述替代点承接 |
| `RichTextView.swift` | 文本编辑桥 | +textDidChangeSelection、+选区矩形、+格式操作（marks/typingAttributes）、+first-responder 观察 | 小改 | EditorSelectionBridge（新） |
| `RichTextBlockView.swift` | 块布局 | +标题框接线（或由 NoteWindowContent 承载）、+顶部内边距适配（工具栏高度）、+上下文行挂载点 | 小改 | — |
| `EditorSelectionBridge.swift`（新） | — | @Observable 选区/焦点/矩形桥 | 新文件 | RichTextView、上下文行 |
| `BlockInsertionControl.swift` | 块插入菜单（死触发） | 修复 hover/选区触发接线 | 小改 | RichTextBlockView |
| `StickyNotesApp.swift` | 场景/命令/快捷键 | +Format 菜单、+View 菜单置顶、+插入图片菜单、toggleNoteWindows 改注册表 | 小改 | MenuCommands、协调器 |
| `MenuCommands.swift` | 命令目录 | +新目录项 | 小改 | MenuChecklistTests |
| `NoteWindowLifecycleTests.swift` | 生命周期 pin | +minSize 220、+关闭反注册断言、fullSizeContentView 转绿 | 改 | — |
| 新测试文件（5） | — | 见 §9 | 新 | — |

**新增文件理由**：`NoteToolbarController`——NSToolbar 是 AppKit 生命周期对象，与窗口同生共死；协调器已 657 行；镜像既有 delegate 持有模式（`windowDelegates`），不引入框架。`AppearancePanelView`——popover 内容用 SwiftUI 最简（既有块视图均为 SwiftUI）。`EditorSelectionBridge`——@Observable 桥使 SwiftUI 订阅选区而无需在 NSTextView delegate 中维护 SwiftUI 状态。StickyCore（SystemBridge/Persistence/Domain）**零改动**（research §5 已验证所有桥接能力已存在）。

## 8. 增量实施阶段（依赖排序）

**Phase 1 — 审计与测试先行（Constitution XII）**
- 定位卡片摘要提取辅助（首行派生复用）、确认新笔记焦点落地位置、锁定 `toggleNoteWindows` 过滤细节。
- 先写红测试：`NoteWindowLifecycleTests`（minSize 220×140、红绿灯关闭→`NoteWindowBridge.isOpen == false`、fullSizeContentView 转绿）、`TitleDerivationTests`（标题/首行/空兜底/截断输入）、`InsertionTargetingTests`（块拆分纯函数）、`FormattingRoundTripTests`（标记应用→canonical 往返）、`AppearancePanelStateTests`（透明度 clamp/重置/数值格式）。
- 交付：全部新测试编译且红灯（除既存 fullSizeContentView 灯）。

**Phase 2 — 窗口镀铬基础 + 工具栏外壳（FR-001/002/003/017a/018）**
- 前置 spike 任务（R1）：标准 NSWindow + `fullSizeContentView` + 透明标题栏 + `NSToolbar` 空工具栏，验证标题渲染、内容延伸、红绿灯不回归（macOS 27 实测）。
- 窗口：styleMask + `.fullSizeContentView`；`contentMinSize = (220, 140)`；`titleVisibility = .visible` + 派生标题 + 同步入口；`windowBackground` 应用透明度。
- `NoteToolbarController` 骨架：toolbar 挂载、固定项标识符、委托、空项验证（无动作）。
- `NoteWindowContent`：移除 `NoteControlsView` 行 + `Divider`；顶部新增标题输入框；上下文菜单迁至内容区；⌥C/⌥O/⌥T overlay 迁移；顶部内边距适配（工具栏高度 + 既有 inset，FR-042 阈值复检）。
- 生命周期：`windowWillClose` 反注册 + 控制器释放（红测试转绿）。
- 验收：应用可运行；窗口打开无控件行；标题显示；既有测试套件（除预期翻转项）全绿。

**Phase 3 — Pin / 外观接线（FR-006/007/008/009/025/026）**
- 工具栏 Pin 项（toggle 按钮 + 图标切换 + `menuFormRepresentation` + View 菜单项）→ `updateAlwaysOnTop`（host→协调器既有路径）。
- 外观项 + `AppearancePanelView`（调色板/透明度/重置/即时预览）→ `updateAppearance` + `updateNotePaper`；外观子菜单迁移（溢出形态）。
- 控制器 `observe` host 状态刷新（置顶/外观）。
- 验收：置顶切换布局零位移；透明度数值完整；面板即时预览；溢出菜单 state 正确。

**Phase 4 — 插入工作流（FR-010/011 + Q4）**
- `resolveInsertionTarget` 纯函数 + 富文本块光标拆分（保留 run 属性、sortKey 重排）+ 特殊块焦点/无上下文降级。
- `insertImageBlock`（新）+ 图片 NSOpenPanel；Insert 下拉菜单组装（截图子菜单/文件/图片/待办/代码）。
- `BlockInsertionControl` 触发修复；菜单 Insert 组新增"插入图片…"。
- 验收：插入目标解析单测全绿；五类插入各路径可用；拖放/菜单/工具栏动作同源。

**Phase 5 — 上下文格式化（FR-012/013/028 + Q5）**
- `EditorSelectionBridge` + `textDidChangeSelection`/选区矩形/first-responder 观察。
- 浮动玻璃胶囊行（macOS 26 guard 内 glassEffect 成组；不抢焦点）。
- Format 菜单 + 快捷键（⌘B/⌘I/⌘U/删除线/代码/字号）；typingAttributes 无选区路径。
- 验收：选择→出现；无选区→消失；菜单常驻；格式往返单测全绿；IME/失焦无副作用。

**Phase 6 — 响应式、边角与无障碍收尾（FR-014/015a/015b/015c/017/019/020/021-024/027/029/030）**
- 宽度矩阵验证（220/320/480/640/800/1200/2000+，§9.1）与连续拖拽检查；内容内边距语义两态（compact 10pt / regular 14–16pt，窗口宽 480 切换；极宽上限 24pt 防居中列）。
- 滚动条审计（保持系统行为，spec FR-020）；激活/失活走查（系统默认，FR-027）。
- 无障碍：标签/tooltip/VoiceOver 走查、Reduce Transparency 等系统模式验证。

**Phase 7 — 回归、多窗口与视觉验证（FR-031-035、SC-001-016）**
- 全量回归套件（§9.3）+ 多窗口独立性 + 截图对比（§9.4）+ 性能核查（§9.5）+ 26/27 兼容验证。

依赖序：1→2→3→4→5→6→7；每阶段结束应用可运行、测试绿。避免"一次性替换一切"提交（工具栏迁移、编辑器改动、生命周期、玻璃各自成提交）。

## 9. 测试与视觉验证

### 9.1 响应式矩阵（源自 Q1/Q2/FR-015a/b/017，非新断点）

| 宽度 | 直接可见动作 | 溢出动作 | 标题行为 | 编辑器可用宽 | 上下文呈现 |
|---|---|---|---|---|---|
| 220–240 pt | 截断标题 + Pin + 溢出 chevron | 外观/插入/更多 | 系统截断（可极小） | ~180 pt（inset 10） | 格式化行照常（若选区） |
| 320 pt | 标题 + Pin + 部分标准项（系统按优先级序） | 剩余标准项 | 截断 | ~280 pt | 同上 |
| 480 pt | Pin/外观/插入/更多全可见 | 无 | 截断至中长 | ~440 pt | 同上 |
| 640 pt | 全部 | 无 | 长标题可全显 | ~600 pt | 同上 |
| 800 pt | 全部 | 无 | 正常 | ~760 pt | 同上 |
| 1200 pt | 全部 | 无 | 正常 | ~1160 pt（inset 16） | 同上 |
| 2000+ pt | 全部 | 无 | 正常 | 宽幅（inset 上限 24，不居中列） | 同上 |

全局不变量（所有宽度）：无重叠/无裁剪/无数值省略号（如"10…"）/无换行/无孤儿图标/无动作不可达/无中心漂移簇/编辑可用/缩放不重置工具栏状态/Pin 切换零位移/溢出命令可用。

### 9.2 测试计划

1. **单元**：标题派生、插入目标解析（含块拆分保留属性）、透明度数值格式（"NN%"）、外观面板 clamp/重置、可见性优先级映射常量。
2. **集成**（host/协调器级）：工具栏动作路由（Pin→updateAlwaysOnTop+持久化；外观→updateAppearance；插入→host 方法）、图片插入资产落位、格式往返（NSTextView→canonical 标记）、溢出 menuFormRepresentation state。
3. **UI/手动**：宽度矩阵逐点 + 连续拖拽；popover 打开时缩放；多窗口独立缩放/置顶；激活/失活。
4. **无障碍**：VoiceOver 标签/value/tooltip；纯键盘（Tab 进工具栏与 chevron、⌘B/⌥C/⌥O/⌥T/⌘W/⌘⌫）；Reduce Transparency/Increase Contrast/Reduce Motion。
5. **OS 版本**：macOS 26 与 27 各走查一遍（CI 用 26 SDK 编译 = 天然验证 availability guard 可编译性）。
6. **多窗口**：3+ 笔记不同宽度并存；各自工具栏状态独立；关闭一个不影响其余。

### 9.3 回归清单（spec 成功标准 15 + 用户输入全项）

打开独立窗口 / 多笔记并存 / 帧恢复（位置+尺寸）/ 关闭行为（红绿灯、⌘W、自动删除语义）/ 内容持久化 / 富文本编辑 / 焦点 / 选区 / undo-redo / 复制粘贴 / 键盘导航 / 拖放（Finder 拖文件）/ 颜色 / 透明度 / 置顶 / 截图 / 图片插入（新）/ 附件 / 块插入 / Todo / Code / Screenshot 块 / 滚动 / 编辑中缩放 / popover 打开时缩放 / 激活失活。既有套件：NoteWindowLifecycleTests、WindowFramePersistenceTests、AppearanceIntegrationTests、NoteCaptureIntegrationTests、MenuChecklistTests、EditorBlockEditingTests、EditorPersistenceTests、ScreenshotCoverAndCaptureTests、FileReferenceAvailabilityTests、WidgetRefreshTests、DeletionToastIntegrationTests、LibraryExceptionGuaranteeTests、NoteContextualActionsTests。

### 9.4 视觉验证（对原始问题态截图对比）

宽度清单截图（220/320/480/640/800/1200/2000+）逐项评估：标题对齐、红绿灯原生性、工具栏密度、垂直镀铬高度（显著低于原控件行，SC-006）、编辑器起点、水平 inset、滚动条存在感、笔记/背景连续性（含 transparency<100% 接缝消除）、玻璃层级、激活/失活、宽窗行为。对比基线 = 当前 main 分支同宽度截图。

### 9.5 性能核查

缩放不重建 NSTextView/模型/块/附件/工具栏对象图（控制器缓存工具栏项）；观察范围仅 `host.note` 外观字段与 selection bridge（编辑文本不触发工具栏重建）；Pin/外观切换不重建 NSWindow；空闲无轮询。验证：001 SC-003/004a/006 回归。

## 10. 风险与缓解

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | fullSizeContentView+透明标题栏+NSToolbar 组合无项目先例（Library spike 失败于私有窗口类） | 标题/内容渲染异常 | Phase 2 前置 1 天 spike；标准 NSWindow 与 MenuBarExtra 场景隔离，已有系统约定背书 |
| R2 | `toggleNoteWindows` 按 title 过滤，派生标题会破坏显示/隐藏全部 | 窗口管理回归 | Phase 2 同步改注册表过滤（`allRegistrations()`） |
| R3 | 富文本块光标拆分（唯一编辑器手术） | 内容损坏/标记丢失 | 纯函数 + 单测（属性保留断言）；Phase 4 独立交付；失败降级=追加末尾（测试覆盖） |
| R4 | 标题派生每击键执行 | 性能 | 字符串级计算 + 按 blocks 变化节流；单测断言无状态泄漏 |
| R5 | 菜单双路由（NotificationCenter+直调）分化 | 动作分裂 | 单操作双路由原则文档化；插入目标解析单点；既有菜单路径不动（避免回归） |
| R6 | 上下文格式化行抢焦点/IME 干扰 | 编辑体验回归 | `refusesFirstResponder` + IME 守卫复用既有 `hasMarkedText` 模式；失焦消失测试 |
| R7 | 极窄宽度系统溢出行为与 Q2 期望不符（系统布局细节） | 220pt 验收 | 宽度矩阵手动+截图验证；Pin 用 `.high` 优先级保障；若 chevron 容纳不下 Pin（系统硬约束），回退 = 提高优先级至 User 级别（单一常量，非断点） |

## 11. 明确非目标（Non-Goals）

- 不做全应用重设计（003 已交付范围不动）；不替换 NSTextView/富文本存储；不重设计块类型；不引入自定义 NSWindow 子类；不模仿 iOS 导航栏；不把笔记面变全玻璃；不自定义关闭按钮；无装饰动画；不要求全部动作常驻可见。
- 不逐选区字号（规范模型无 per-run 字号，research §5）；不实现自定义工具栏定制面板（Q3）；不实现 `/` 命令系统（003 FR-043 既有语义）；不修改 StickyCore 模块。
- 不手写滚动条/不覆写系统滚动偏好（spec FR-020）；不在 Reduce Transparency 下手工复刻玻璃。

## 12. 剩余阻塞项（Blockers）

- 无产品级阻塞。规划级微决策（已定默认，实施可微调）：标题空兜底文案"无标题笔记"（本地化，zh-Hans/en）；新笔记打开焦点落点（默认：内容顶部标题框，Phase 1 审计确认现状后锁定）；工具栏按钮图标集（pin/pin.fill、paintpalette、plus、ellipsis.circle——全部 SF Symbols，spec FR-029 语义内）。

**T003 审计结论（2026-08-10 记录）**：

- **首行/摘要提取辅助**：`NoteSummary.generatedSummary(for:)`（`Packages/StickyCore/Sources/Domain/NoteSummary.swift:32`，maxLength 80 裁剪）与 `displayTitle`（:75）。标题派生按 spec FR-003 语义需要**完整首行**（不裁剪，标题栏系统省略号负责截断）——故 App 层新增 `NoteWindowDerivations.firstMeaningfulLine(blocks:)` 与 `firstLine(of:)`（`App/Sources/Features/NoteWindow/NoteWindowDerivations.swift`），提取语义镜像 NoteSummary（首非空 richText/todo/code 行 → 文件显示名/说明/占位），StickyCore 零改动。
- **新笔记窗口焦点落点**：现状为 `open(noteId:)` 末尾 `window.makeKeyAndOrderFront` + `NSApplication.activate`（`NoteWindowCoordinator.swift` open() 尾部），无显式 first-responder 设置——焦点实际落到 SwiftUI 首个可聚焦元素（新设计下为内容顶部标题框，符合 FR-003 默认）。锁定：不在 open() 中强制设置 first responder（避免与 IME/焦点纪律冲突），标题框为自然落点。
- **T012 追加事实**：macOS 27 实测——NSHostingView 会把自己的 SwiftUI 内在最小尺寸（ScrollView → 约 0×52）传播覆盖 `contentMinSize`；`open()` 必须在前台布局后同步重设（`layoutSubtreeIfNeeded` + 重设，`windowDidResize` 中复检）。已实现并锁死（T004 断言 220×140）。

## 13. /speckit.tasks 就绪评估

**已解决（无需实现者自行发明）**：工具栏架构（§3.1-3.3）、项优先级映射（§3.2 表）、状态所有权（§2.3）、标题行为（§3.4）、AppKit/SwiftUI 边界（§2.1-2.2）、Liquid Glass 范围（§5，唯一自定义面 + 明确拒绝清单）、可用性策略（§6 矩阵 + research §3 证据）、响应式策略（§9.1 + 系统溢出）、迁移顺序（§8）、回归标准（§9.3）。

**结论：规划已充分解决，可以进入 /speckit.tasks。** 唯一建议：Phase 1 的首个任务先锁定"新笔记焦点落点"与"卡片摘要提取辅助复用点"两个代码事实，避免 Phase 2/3 返工。
