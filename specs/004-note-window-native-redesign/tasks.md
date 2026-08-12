---

description: "Task list for feature 004: 独立笔记窗口原生镀铬与自适应重设计"

---

# Tasks: 独立笔记窗口原生镀铬与自适应重设计（Native Toolbar + Liquid Glass）

**Input**: Design documents from `/specs/004-note-window-native-redesign/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Constitution XII（测试先行）与 spec "Required Tests" 均强制测试——每个用户故事阶段的测试任务必须**先写、先红**，再实现。所有 Swift Testing 套件需 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` 前缀（AGENTS.md）。

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- 应用源码: `App/Sources/...`（feature-area 布局，见 plan.md Project Structure）
- 测试: `AppTests/`（Swift Testing）；StickyCore 包 `Packages/StickyCore/` 本特性零改动
- 设计文档: `specs/004-note-window-native-redesign/`（plan.md 为执行顺序权威；spec.md 为行为权威）

## Phase 1: Setup（共享基础设施）

**Purpose**: 基线确认与验证前置

- [X] T001 运行基线测试套件（`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'`），确认 `NoteWindowLifecycleTests.swift:114` fullSizeContentView 断言为唯一红灯，记录其余全绿基线
- [X] T002 ~~在宽度清单（320/480/640/800/1200/2000+ pt）为当前 main 行为的笔记窗口各截一张基线截图（含 100% 与 60% 透明度各一张），存入 `specs/004-note-window-native-redesign/checklists/baseline-screenshots/`（Phase 9 视觉对比用）~~（2026-08-13 用户决策取消：不做截图对比流程）

---

## Phase 2: Foundational（阻塞性前置）

**Purpose**: 测试先行（Constitution XII）+ 代码事实审计 + 技术 spike。**任何用户故事开始前必须完成。**

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 代码事实审计：确认新笔记窗口打开时键盘焦点实际落点（NSHostingView/NSTextView first responder 现状），并在 `Packages/StickyCore/Sources/Domain/` 与 `App/Sources/Features/Library/` 定位卡片摘要/内容首行提取辅助函数（001 FR-020/021，CardProjection 摘要逻辑），记录 file:line 供标题派生复用；结论写入 plan.md §12 备注
- [X] T004 修改 `AppTests/NoteWindowLifecycleTests.swift`：新增"`window.contentMinSize` == 320×140"断言（FR-017a/Q6，2026-08-13 修订；原 220×140 被 Q6 取代，先红）
- [X] T005 [P] 在 `AppTests/NoteWindowLifecycleTests.swift` 新增关闭反注册测试：红绿灯 `window.close()` 后 `NoteWindowBridge.isOpen(noteId:)` 必须为 false，再次 `open(noteId:)` 创建全新窗口（修复既有死 host 复活缺陷，先红）
- [X] T006 [P] 新建 `AppTests/TitleDerivationTests.swift`：`deriveWindowTitle` 纯函数——手动标题优先/首行派生/空兜底本地化"无标题笔记"/长输入不截断值（spec FR-003，先红）
- [X] T007 [P] 新建 `AppTests/InsertionTargetingTests.swift`：`resolveInsertionTarget`（caretSplit/afterBlock/append 三态）与 `splitRichTextBlock`（run 属性与标记保留、sortKey 中间值）纯函数断言（spec FR-010/Q4，先红）
- [X] T008 [P] 新建 `AppTests/FormattingRoundTripTests.swift`：NSTextView 上应用 bold/italic/underline/strikethrough/inlineCode → `canonicalDocument` 往返标记保留；typingAttributes 无选区路径（FR-012/FR-053，先红）
- [X] T009 [P] 新建 `AppTests/AppearancePanelStateTests.swift`：透明度 clamp 0.40–1.00/步 0.05、"NN%" 数值格式（禁止 "10…"）、重置=默认色+1.0（spec FR-008/009，先红）
- [X] T010 [P] 新建 `AppTests/NoteToolbarStateTests.swift`：`toolbarVisibilityPriority` 映射（Pin=.high，其余 .standard，FR-015a）与工具栏项标识符固定集常量断言（FR-015c/Q3，先红）
- [X] T011 Spike（手动验证，结果记录进 `research.md` §1）：标准 NSWindow + `.fullSizeContentView` + `titlebarAppearsTransparent` + 空 `NSToolbar` 组合——验证内容延伸至标题栏下、红绿灯正常（macOS 27 实测；R1 缓解；Q7 起标题不再渲染于标题栏）

**Checkpoint**: Foundation ready - 全部新测试编译且红灯（除既有 fullSizeContentView 灯）；spike 结论记录完成；用户故事实现可开始

---

## Phase 3: User Story 1 - 原生镀铬的独立笔记窗口 (Priority: P1) 🎯 MVP

**Goal**: 标准 macOS 标题栏 + 系统窗口工具栏取代 NoteControlsView 控件行；标题为内容首行（标题栏不渲染标题文本，Q7）；置顶/更多进工具栏；生命周期修复。窗口在移除控件行后依旧完整可用（spec US1；plan Phase 2–3）。

**Independent Test**: 打开有/无标题笔记 → 内容首行标题正确（唯一可见）、标题栏无标题文本、工具栏四入口可见、无自定义关闭按钮、关闭走红绿灯且再次打开为全新窗口、置顶可用、内容首行贴近工具栏；`xcodebuild test` 既有生命周期/帧持久化/外观套件全绿。

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**（T004/T005 已在 Foundational 先写）

### Implementation for User Story 1

- [X] T012 [US1] 窗口镀铬：`App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` `open(noteId:)` 中 styleMask 追加 `.fullSizeContentView`、`contentMinSize = NSSize(width: 320, height: 140)`（替换 300×200，FR-001/017a；Q6 修订）
- [X] T013 [US1] 标题模型：`NoteWindowCoordinator.swift` 中 `titleVisibility = .hidden`（Q7：标题栏不渲染标题文本）、`updateWindowTitle(noteId:)`（`Note.title` → 首行 → 兜底，复用 T003 定位的摘要辅助；window.title 隐藏派生供 Mission Control/窗口菜单/VoiceOver）+ 打开时初值；`NoteWindowContent` 以 `.onChange(of: host.note?.title)` 与 `.onChange(of: host.blocks)` 触发同步（FR-003）
- [X] T014 [US1] 内容层统一：`App/Sources/Features/NoteWindow/ReadableTheme.swift` `windowBackground(for:)` 应用 `note.transparency`（与纸面一致，消除 transparency<100% 接缝）；**不得**触碰 `window.alphaValue`
- [X] T015 [US1] 生命周期修复：`NoteWindowCoordinator.swift` `NoteWindowDelegate.windowWillClose` 增加 `NoteWindowBridge.unregister` + 释放工具栏控制器（与 ⌘W 路径对齐）；T005 转绿
- [X] T016 [US1] 新建 `App/Sources/Features/NoteWindow/NoteToolbarController.swift`：@MainActor 类，NSToolbar 创建（identifier `note.window.toolbar`）、固定项标识符集（`note.toolbar.pin/appearance/insert/more`）、`itemForItemIdentifier` 委托单点构造 + 项缓存（窗口生命周期内不重建）、挂载 `window.toolbar`；由协调器 `toolbars[noteId]` 持有，与 delegate 同释放（plan §3.1/contracts §1）
- [X] T017 [US1] 内容结构重组：`NoteWindowCoordinator.swift` `NoteWindowContent` 移除 `NoteControlsView` + `Divider`；顶部新增标题输入框（唯一可见标题呈现、视觉区分——Q7 Apple Notes 模式：`.title2` bold + 灰色占位；编辑→`updateAppearance`，空→nil，001 FR-050 语义）；顶部内边距适配（工具栏高度 + 既有 inset，FR-018/FR-042 阈值复检）
- [X] T018 [US1] 迁移动画/快捷键：`NoteWindowContent` 增加 ⌥C/⌥O/⌥T 隐藏按钮 overlay（从 NoteControlsView 迁移，键位与行为不变）
- [X] T019 [US1] 上下文菜单迁移：内容区 `.contextMenu` 承载复制笔记/复制为 Markdown/导出 JSON…/移入废纸篓/外观子菜单/小组件项（原 NoteControlsView 上下文菜单语义，001 FR-031）
- [X] T020 [US1] Pin 工具栏项：`NoteToolbarController` 中置顶项——NSButton（`bezelStyle = .toolbar`，macOS 26 guard 内 `.glass`，`setButtonType(.toggle)`）、图标 pin/pin.fill 随 state、`visibilityPriority = .high`（FR-015a）、`menuFormRepresentation` = 带 state 的 toggle NSMenuItem、tooltip + `accessibilityValue` 开/关；动作 → `coordinator.updateAlwaysOnTop`（唯一入口）；`observe` host `alwaysOnTop` 刷新状态；切换零几何位移
- [X] T021 [US1] View 菜单置顶项：`App/Sources/App/StickyNotesApp.swift` 增加 "Always on Top"（toggle，作用于 key 笔记窗口）+ `App/Sources/App/MenuCommands.swift` 目录条目（003 FR-072 语义）
- [X] T022 [US1] More 工具栏项：ellipsis.circle 按钮 + NSMenu（复制笔记/复制为 Markdown/导出 JSON…/移入废纸篓 ⌘⌫/分隔/允许小组件 toggle/设为小组件笔记·移除），复用 `NoteWindowContent` 既有闭包（duplicate/copy/export/moveToTrash/widget 选择），`menuFormRepresentation` 同源
- [X] T023 [US1] 窗口管理修复：`StickyNotesApp.swift` `toggleNoteWindows` 改用 `NoteWindowBridge.allRegistrations()` 过滤（不再按 title，R2）
- [X] T024 [US1] 删除 `App/Sources/Features/NoteWindow/NoteControlsView.swift`（T017–T019 迁移完成后，确认无引用）
- [X] T025 [US1] 验证：全量 `xcodebuild test`（生命周期/帧持久化/外观/上下文/捕获/MenuChecklist 套件）+ quickstart §3.1 手动走查（标题/关闭重开/置顶/接缝）+ 置顶切换前后截图对比（几何零位移，FR-007）

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently（MVP：原生镀铬 + 标题 + 置顶 + 更多 + 生命周期修复）

---

## Phase 4: User Story 3 - 外观：一个入口搞定颜色与透明度 (Priority: P2)

**Goal**: 工具栏 Appearance 项 → NSPopover 面板（颜色 7 键 + 透明度 Slider + 完整数值 + 重置），即时预览（spec US3；plan Phase 3）。依赖 US1 工具栏外壳。

**Independent Test**: 点 Appearance → 换色/调透明度/读数值/重置全部可用且即时生效；透明度数值任何宽度完整；DB 持久化（重开保留）。

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**（T009 已在 Foundational 先写）

### Implementation for User Story 3

- [X] T026 [P] [US3] 新建 `App/Sources/Features/NoteWindow/AppearancePanelView.swift`（SwiftUI）：7 键调色板（`NotePaletteKey` 含 custom，`paletteStorage` 映射逐字保留，选中=勾选+名称+色块）、透明度 Slider 0.40–1.00/0.05、"NN%" 完整数值标签、恢复默认按钮（默认色+1.0）、无障碍 label/value（FR-008/009，001 FR-044）
- [X] T027 [US3] Appearance 工具栏项：`NoteToolbarController` 中 paintpalette 按钮 → `NSPopover`（`NSHostingController` → `AppearancePanelView`，非激活式锚定）；改动 → `host.updateAppearance` + `coordinator.updateNotePaper`（即时预览，无确认按钮）；`menuFormRepresentation` = 外观子菜单（颜色 7 项 + 透明度 13 步 + 重置，自 NoteControlsView 上下文菜单迁移）
- [X] T028 [US3] 状态同步：控制器 `observe` host 外观字段（colorKey/customColor/transparency）→ 刷新面板与项状态（Observation，macOS 14+；无 NotificationCenter 新用法）
- [X] T029 [US3] 验证：`AppearancePanelStateTests` 转绿 + quickstart §3.3.2 手动走查（含 transparency 60% 下标题栏/工具栏玻璃观感与对比度复检）

**Checkpoint**: US3 独立可用；US1+US3 并存无回归

---

## Phase 5: User Story 4 - 插入：一个入口聚合所有插入 (Priority: P2)

**Goal**: 工具栏 Insert 下拉菜单（截图/图片/文件/待办/代码）+ 插入目标解析（光标拆分/块后/末尾）+ 图片插入新路径 + BlockInsertionControl 修复（spec US4；plan Phase 4）。依赖 US1。

**Independent Test**: 通过 Insert 菜单完成截图、文件、**图片**（新）、待办、代码插入；光标处拆分插入标记保留；无焦点时追加末尾；编辑器内 `+` 悬停出现且动作同源。

### Tests for User Story 4 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**（T007 已在 Foundational 先写）

### Implementation for User Story 4

- [X] T030 [US4] 插入目标解析实现：`NoteWindowCoordinator.swift`/`NoteWindowHostModel.swift` 落地 `resolveInsertionTarget` 与 `splitRichTextBlock`（保留 run 属性；新块中间 `sortKey`；特殊块焦点→afterBlock；无上下文→append 既有一致）
- [X] T031 [US4] 图片插入新路径：`NoteWindowHostModel.swift` 新增 `insertImageBlock`（NSOpenPanel 图片类型 → 资产导入复用截图管线（镜像 `captureScreenshot` :408-436 模式）→ `.image` 块）；`.image` 块创建能力补齐
- [X] T032 [US4] Insert 工具栏项：`NoteToolbarController` 中 plus 按钮（pullsDown）→ NSMenu：截图子菜单（区域/窗口，既有 `captureScreenshot` 流程含权限确认）、插入文件引用…（既有 `pickAndInsertFileReference`）、插入图片…（T031）、待办（⇧⌘T）、代码块（⇧⌘C）；`menuFormRepresentation` 同源；异步流程发起时快照插入目标，失效降级 append
- [X] T033 [US4] 插入目标接线：既有 host 插入方法（todo/code/fileRef/image/screenshot）统一携带目标上下文（contracts §5）；应用菜单路径（NotificationCenter → keyHost）与工具栏直调共用同一 host 操作（单操作双路由，spec FR-010 防两套系统）
- [X] T034 [US4] `App/Sources/Features/Editor/BlockInsertionControl.swift` 触发修复：`isCursorLineHovered`（onHover）与 `isTextSelected`（selection bridge）接线，使 `+` 上下文控件真实出现（003 FR-043/004 FR-010）
- [X] T035 [US4] 菜单同步：`StickyNotesApp.swift` Insert 组新增"插入图片…" + `MenuCommands.swift` 目录条目（与 T040/T047 串行，避免同文件冲突）
- [X] T036 [US4] 验证：`InsertionTargetingTests` 转绿 + host 级插入集成测试（图片资产落位/五类插入/拖放与菜单同源）+ quickstart §3.3.3 手动走查

**Checkpoint**: US4 独立可用；无第二套插入系统

---

## Phase 6: User Story 5 - 格式化只在需要时出现 (Priority: P2)

**Goal**: 选区观察 + 上下文浮动玻璃格式行 + Format 菜单；NSTextView 为格式权威（spec US5；plan Phase 5）。依赖 US1；逻辑上需要 US4 的 BlockInsertionControl 触发（共用 selection bridge）。

**Independent Test**: 选中文本 → 浮动行出现（B/I/U/删除线/代码/字号）；无选区/失焦消失；Format 菜单与 ⌘B/⌘I/⌘U 常驻可用；无选区时作用于后续输入；IME 组合不触发。

### Tests for User Story 5 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**（T008 已在 Foundational 先写）

### Implementation for User Story 5

- [X] T037 [P] [US5] 选区桥：`App/Sources/Features/Editor/RichTextView.swift` 新增 `textDidChangeSelection` + 选区矩形（layoutManager → 窗口坐标）+ first-responder 观察；新建 `App/Sources/Features/Editor/EditorSelectionBridge.swift`（@Observable，只读投影，不写回编辑器）
- [X] T038 [US5] 格式操作：`RichTextView.Coordinator` 新增 `applyMarks`（bold/italic/underline/strikethrough/inlineCode）——有选区作用于 textStorage，无选区作用于 typingAttributes；`hasMarkedText()` 期间不应用（IME 守卫复用既有模式）
- [X] T039 [US5] 上下文格式行：`NoteWindowContent`/`RichTextBlockView` 挂载浮动胶囊行（SwiftUI 标准按钮 + 容器 `glassEffect(.regular)` + `glassEffectID/union` 成组，macOS 26 guard；按钮 `refusesFirstResponder` 不抢焦点；无选区/失焦消失），锚定于选区上方（T037 矩形）
- [X] T040 [US5] Format 菜单：`StickyNotesApp.swift` 新增 Format 组（粗体 ⌘B/斜体 ⌘I/下划线 ⌘U/删除线/代码样式/文本大小 9–24 全列表）+ `MenuCommands.swift` 目录条目；作用于 key 窗口 active NSTextView
- [X] T041 [US5] 验证：`FormattingRoundTripTests` 转绿 + 手动走查（quickstart §3.3.4：选区/失焦/菜单/无选区 typing/IME/中英混排）

**Checkpoint**: US5 独立可用；格式权威单一（NSTextView）

---

## Phase 7: User Story 2 - 320 到 2000+ pt 始终是同一个窗口 (Priority: P1)

**Goal**: 宽度矩阵验证 + 语义内边距 + 系统溢出行为确认（spec US2；plan Phase 6）。**执行顺序说明**：US2 为 P1 但其验证对象（四项工具栏+标题+上下文 UI）需 US1/3/4/5 落位后才可完整验证，故按 plan.md §8 依赖序置于其后。

**Independent Test**: 320→2000+ pt 连续拖拽全程：无畸形/裁剪/截断数值/重叠/换行/图标残留/功能不可达；Pin 最后进溢出；内容首行标题截断；编辑器可用宽保持。

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**（T010 已在 Foundational 先写）

### Implementation for User Story 2

- [X] T042 [US2] 语义内边距：`NoteWindowContent` 内容水平内边距两态（compact 10pt / regular 14–16pt，以窗口宽度 480 切换；极宽上限 24pt 防居中列）——唯一允许的自定义宽度感知规则（NSToolbar 无法表达内容内边距，plan §5/§8 明示理由；不引入更多断点）
- [X] T043 [US2] 溢出行为确认：宽度清单（320/480/640/800/1200/2000+）逐点核对 FR-015a/015b（320：Pin+chevron 直接可见；外观/插入/更多进溢出；全部可发现可执行；标题在内容首行不参与溢出体系，Q7）；若系统溢出与期望不符，仅允许调整单一可见性优先级常量（R7 回退，记录于 plan.md §10）
- [X] T044 [US2] 滚动条审计：`RichTextView`/`NoteWindowContent` 无自定义滚动条样式、无覆盖层；行为跟随系统偏好（spec FR-020）；窄宽度滚动条占比与缩放中无水平裁剪/文本容器宽度突变/布局跳动
- [X] T045 [US2] 弹层与缩放：popover/菜单打开时缩放窗口无崩溃/布局错乱；连续拖拽不重置工具栏状态（Pin 状态保持）；无中心漂移簇、无标题栏/编辑器坐标系分叉观感（FR-017 全局不变量清单逐项过检）【代码级审计：外观 popover `.transient` + 标准 NSMenu（FR-014 系统默认行为）；窗口缩放路径仅 min-size 复检，无任何重置工具栏状态的处理；287 App 测试全绿；连续拖拽走查留 quickstart §3.2】
- [ ] T046 [US2] 验证：`NoteToolbarStateTests` 转绿（全量 App 测试含 NoteToolbarStateTests 全绿✅）+ quickstart §3.2 连续拖拽验收（人工）；~~全矩阵截图存入 `checklists/width-matrix/`~~（2026-08-13 用户决策取消截图流程）

**Checkpoint**: US2 独立可用；响应式主要由系统机制提供（代码审查：除内边距两态外无新增手写断点）

---

## Phase 8: User Story 6 - 键盘、无障碍与系统行为 (Priority: P3)

**Goal**: 菜单命令目录同步、无障碍标签/工具提示/键盘走查、系统外观模式与激活失活验证（spec US6；plan Phase 6 无障碍部分 + FR-011/029/027/035）。

**Independent Test**: VoiceOver 读全工具栏项/面板/格式行；纯键盘完成全部重要动作；Reduce Transparency/深色/失活下可读可用。

### Tests for User Story 6 ⚠️

> **NOTE**: 以手动走查清单为主（AppUITests 受 macOS 27 beta 无头环境限制，沿用既有策略）

### Implementation for User Story 6

- [X] T047 [US6] 命令目录收口：核对 Always on Top/Format 组/插入图片… 全部新条目与 `MenuChecklistTests` 断言一一对应（003 FR-072/SC-017 语义）；仅补齐遗漏，不重复已同步条目
- [X] T048 [US6] 无障碍走查：全部图标控件 `accessibilityLabel`/`accessibilityValue`（置顶开/关、透明度数值、颜色选中）/tooltip（`toolTip`/`.help`）；VoiceOver 读出工具栏、溢出菜单、外观面板、格式行；焦点顺序随溢出进出可预测（FR-029/001 FR-180b）【代码级审计：四项工具栏按钮均有 accessibilityLabel+toolTip，Pin 另带 accessibilityValue 开/关与溢出 toggle state；面板色板/透明度滑块有 label/value；VoiceOver 实读留 quickstart §3.4 人工】
- [X] T049 [US6] 键盘走查：Tab 进工具栏与 chevron、⌥C/⌥O/⌥T、⌘B/⌘I/⌘U、⇧⌘T/⇧⌘C、⌘W、⌘⌫ 全路径验证；格式行不打断编辑焦点（FR-029）【代码级审计：⌥C/⌥O/⌥T overlay（NoteWindowContent :672-746）、⌘B/⌘I/⌘U/⇧⌘T/⇧⌘C/⌘W/⌘⌫ 全部 keyboardShortcut 在案且 MenuChecklistTests 全绿；格式行按钮 refusesFirstResponder；Tab 实走留 quickstart §3.4 人工】
- [X] T050 [US6] 系统模式：Reduce Transparency / Increase Contrast / Reduce Motion / 深色模式 / 激活-失活窗口逐项走查（玻璃降级由系统处理，不手工复刻；失活内容可读——FR-027/035/FR-063 语义）【代码级审计：全部玻璃外观为系统提供（bezelStyle .glass/glassEffect 均 #available 守卫，T051 已核），零自定义材质/降级复刻代码；失活浮动行隐藏行为已实现并经新增 windowDeactivationClearsEditorFocusFlag 测试锁定（FR-012）；逐模式实走留 quickstart §3.4 人工】
- [X] T051 [US6] 版本兼容：以 macOS 26 SDK 语义复查全部 `#available` 守卫（CI 编译即验证）；macOS 26 与 27 各运行一次关键路径（可用性矩阵 plan §6）

**Checkpoint**: US6 独立可用；全部故事完成，进入收尾

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: 回归、多窗口、视觉对比、性能与完成度审计（plan Phase 7）

- [X] T052 [P] 全量回归：`AppTests` + `Packages/StickyCore` 全部套件绿（含既有 12+ 套件与新增 5 文件；spec 成功标准 15）
- [X] T053 [P] 多窗口验证：3+ 笔记不同宽度并存，各自独立缩放/置顶/外观/格式化状态；关闭一个不影响其余；激活/失活正确（spec 成功标准 14）【代码级审计+测试：每窗口独立 toolbars/hosts/windowDelegates 字典 + 按 noteId 的 bridges 注册表；新增 windowDeactivationClearsEditorFocusFlag 双窗口 key 互斥测试全绿；trafficLightCloseUnregistersAndReopenCreatesFreshWindow 覆盖关闭隔离；3 窗口实走留 quickstart §3.3.5 人工】
- [X] T054 ~~[P] 视觉对比：T002 基线截图 vs 实现后同条件截图（宽度清单 × 100%/60% 透明度），逐项评估 plan §9.4（标题对齐/红绿灯原生/镀铬高度显著下降/编辑器起点与 inset/滚动条/背景连续性/玻璃层级/激活失活/宽窗）~~（2026-08-13 用户决策取消：截图对比流程取消，T002/T046 截图部分同步取消）
- [X] T055 [P] 性能核查：连续缩放无卡顿、缩放/打字/选区变化不重建 NSTextView/块/工具栏对象图、Pin/外观切换不重建 NSWindow、空闲无轮询（001 SC-003/004a/006）
- [X] T056 完成度审计：`specs/004-note-window-native-redesign/quickstart.md` 全场景走查 + spec 成功标准 SC-001~016 逐条核对 + 文档（spec/plan/research/contracts/data-model）与实现同步【文档同步完成（2026-08-10 clarify+implement pass；2026-08-13 Q6/Q7 pass）：spec FR-003/008/010/012/014/015b/017/019/025/031 澄清落位，2026-08-13 新增 Q6（最小宽度 320）/Q7（Apple Notes 标题模式）改写 FR-003/015a/015b/017a/SC-004/005a/011；contracts §4 补 key-state 重发布契约，§6 标题契约 Q7 修订；research §2 Q1 最小高 140 pt 对齐；data-model §2 桥职责补注；自动套件 App + StickyCore 全绿；SC 视觉/走查类留人工（连续拖拽，T046；截图对比流程 2026-08-13 用户决策取消）】
- [X] T057 提交序列：按 AGENTS.md 约定（conventional commits，中 body，FR 引用）分阶段提交：镀铬+生命周期 → 外观 → 插入 → 格式化 → 响应式/无障碍 → 回归收尾；每提交前 `git status`/`git diff` 检查，禁止提交 secrets/真实笔记内容

---

## Phase 10: 收口修正（320 最小宽度 + Apple Notes 标题模式）

**Purpose**: 2026-08-13 会话决策（Q6/Q7）：最小宽度 220→320 pt（合适常规值、标题允许截断、最小宽保持美观）；标题走 Apple Notes 模式——仅内容顶部首行呈现一次且可编辑（视觉区分），标题栏不渲染标题文本，`window.title` 隐藏派生（Mission Control/窗口菜单/VoiceOver）。测试先行后落地并全量同步工件。

- [X] T058 测试先行（先红后绿）：`AppTests/NoteWindowLifecycleTests.swift` minSize 断言 220×140→320×140（Q6）+ 新增 `titleVisibility == .hidden` 与 `window.title` 派生断言（Q7）；红灯确认（2 issues）后实现转绿
- [X] T059 实现：`NoteWindowCoordinator.swift` contentMinSize 三处 220→320 + `titleVisibility = .hidden`（保留 `updateWindowTitle`）；`RichTextBlockView.swift` 标题框 `.title2.weight(.bold)` + 占位符改 `String(localized: "editor.titleField", defaultValue: "Title")`
- [X] T060 工件同步与回归：spec（Q6/Q7 决策记录 + FR-003/015/015a/015b/017/017a/SC-001/004/005a/011 改写）、plan（§3.2/§3.4/§9.1/§9.4/R7 等）、quickstart §3.1/§3.2、contracts §6、data-model §3/§6、tasks 各引用同步；全量 `xcodebuild test` 绿
- [X] T061 标题/正文左线对齐（SC-004，2026-08-13 用户反馈"标题与正文没有共用同一条左边线"）：`RichTextView` 新增对齐常量（textContainerHorizontalInset=0、lineFragmentPadding=0、垂直 inset 16 保留）并接线 `makeNSView`；`EditorBlockEditingTests` 新增对齐断言（先红 2 issues → 实现转绿）
- [X] T062 标题→正文垂直间距压缩（2026-08-13 用户反馈"间距略大，像文章编辑器"）：`RichTextBlockView` VStack spacing 10→8 + BlockInsertionControl 底部 padding 2→0 + `RichTextView` 垂直 inset 16→12（合计约 -26%，便签感）；`EditorBlockEditingTests.bodyVerticalBreathingRoomPreserved` 断言先红（16≠12）→ 实现转绿；Toolbar→标题间距不动

**Checkpoint**: Q6/Q7 收口完成；320 起连续拖拽验收 + 标题单源观感留人工验证（T046；截图对比流程已按 2026-08-13 用户决策取消）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories（审计/红测试/spike 全部前置）
- **User Stories (Phase 3+)**: 均依赖 Foundational；故事间顺序遵循 plan.md §8 依赖序（非并行——同一 `NoteWindowCoordinator.swift`/`StickyNotesApp.swift` 被多故事触碰，串行实现避免同文件冲突）
- **Polish (Phase 9)**: Depends on all user stories complete
- **Phase 10（Q6/Q7 收口修正）**: 依赖全部故事完成；测试先行（T058 红→绿）→ 实现（T059）→ 工件同步+回归（T060）

### User Story Dependencies

- **US1 (P1)**: Foundational 后即可开始——无故事依赖（MVP 载体）
- **US3 (P2)**: 依赖 US1（工具栏外壳）
- **US4 (P2)**: 依赖 US1（Insert 项）；与 US5 共用 selection bridge 但可串行
- **US5 (P2)**: 依赖 US1（T037 桥先行；逻辑依赖 US4 的 T034 触发接线）
- **US2 (P1)**: 依赖 US1/3/4/5 全部落位（验证对象完整；plan §8 明示顺序）
- **US6 (P3)**: 依赖 US1/3/4/5（菜单目录收口需全部新命令存在）

### Within Each User Story

- Tests MUST be written and FAIL before implementation（T004–T010 Foundational 已统一先写）
- 纯函数（标题派生/插入目标/优先级映射）先于 UI 接线
- 核心实现先于集成验证；故事完成再进入下一优先级

### Parallel Opportunities

- Phase 1 两任务可并行（基线测试与截图互不依赖）
- Phase 2 红测试任务 T005–T010 全 [P] 可并行（不同测试文件）
- 同一文件（`NoteWindowCoordinator.swift`、`NoteToolbarController.swift`、`StickyNotesApp.swift`、`MenuCommands.swift`）内的任务**串行**（未标 [P]）
- Phase 9 T052–T055 可并行（不同验证面）；T057 最后串行

---

## Parallel Example: Foundational 红测试

```bash
# Launch all red tests together（不同测试文件）:
Task: "T005 NoteWindowLifecycleTests 关闭反注册断言"
Task: "T006 TitleDerivationTests 新建"
Task: "T007 InsertionTargetingTests 新建"
Task: "T008 FormattingRoundTripTests 新建"
Task: "T009 AppearancePanelStateTests 新建"
Task: "T010 NoteToolbarStateTests 新建"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. 完成 Phase 1: Setup（基线）
2. 完成 Phase 2: Foundational（CRITICAL - 红测试 + 审计 + spike）
3. 完成 Phase 3: US1（原生镀铬 + 标题 + 置顶 + 更多 + 生命周期修复）
4. **STOP and VALIDATE**: US1 独立验收（T025：全量测试 + 手动走查）
5. 交付/演示——MVP 已成立：窗口从此具备原生镀铬、无控件行、生命周期正确

### Incremental Delivery

1. Setup + Foundational → Foundation ready（红测试灯全亮）
2. US1 → 测试独立通过 → MVP 演示
3. US3 外观 → 独立验证 → 演示
4. US4 插入 → 独立验证 → 演示
5. US5 格式化 → 独立验证 → 演示
6. US2 响应式验证 → US6 无障碍 → Polish 收尾
7. 每故事不破坏前序故事（全量测试门禁）

### Parallel Team Strategy

- 本特性受同一批文件（协调器/内容/应用/菜单）强耦合约束，**建议单人串行或双人按文件所有权并行**（如：A 负责 NoteWindowCoordinator.swift + NoteToolbarController.swift；B 负责 RichTextView/EditorSelectionBridge + 测试文件）——并行组合示例：A 走 US1（T012–T025）期间，B 可并行完成 US5 的 T037（RichTextView/EditorSelectionBridge，文件不重叠）

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- 测试先行的灯：T004–T010（Foundational）红 → 对应实现转绿；既有 fullSizeContentView 灯（`NoteWindowLifecycleTests.swift:114`）在 T012 转绿
- 同文件冲突清单：`NoteWindowCoordinator.swift`（T012–T017、T030）、`NoteToolbarController.swift`（T016/T020/T022/T027/T032）、`StickyNotesApp.swift`（T021/T023/T035/T040/T047）、`MenuCommands.swift`（T021/T035/T040/T047）——串行
- 提交规范：AGENTS.md conventional commits（`feat(app): :emoji: 中文主述` + body 按模块）；FR 编号引用；禁 secrets/真实笔记内容
- 每阶段结束跑 `DEVELOPER_DIR=… xcodebuild test` 全量门禁；CI 保持 Xcode 26 兼容（macOS 26 部署目标不得变更）
- 不确定时以 spec.md（行为）→ plan.md（工程）→ contracts/（接口）→ research.md（API 证据）优先级为准；发现文档矛盾时按 AGENTS.md 流程回退到会话原文
