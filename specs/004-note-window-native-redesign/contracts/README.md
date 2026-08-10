# Contracts: 独立笔记窗口原生镀铬与自适应重设计

**Date**: 2026-08-10 | **Spec**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

本目录记录本特性的**内部接口契约**（App 层组件间）。系统外部接口（GRDB schema、同步协议、菜单栏行为）无变更。契约以行为语义为主，不规定逐行实现。

## 1. `NoteToolbarController` ↔ `NoteWindowCoordinator`

- 生命周期：`coordinator` 在 `open(noteId:)` 中创建控制器并存入 `toolbars[noteId]`（与 `windowDelegates` 同模式）；在释放 delegate/host 的同一路径释放。控制器不得自行持有 NSWindow 强引用。
- 创建入参：`noteId`、host（弱语义引用，经协调器传递）、协调器方法集闭包。
- 协调器提供（控制器调用）：
  - `updateAlwaysOnTop(noteId:)`——置顶唯一入口（含 `WindowLevelBridge` + 集合行为 + 持久化前置）。
  - `updateNotePaper(noteId:)`——外观即时预览重刷窗口背景。
  - `updateWindowTitle(noteId:)`——派生标题推送到 `window.title`。
  - 插入动作集（截图/文件/图片/待办/代码）与 More 动作集（复制/导出/移入废纸篓/小组件）——复用 `NoteWindowContent` 现有闭包语义，避免重复实现。
- 控制器提供（协调器调用）：`syncState()`（窗口打开时初始同步）、`refreshFromHost()`（host 状态变化时刷新项状态/标题）。

## 2. 工具栏项契约（NSToolbarDelegate）

- 标识符固定集：`note.toolbar.pin` / `note.toolbar.appearance` / `note.toolbar.insert` / `note.toolbar.more`。
- `defaultItemIdentifiers` = 上列全集；`allowedItemIdentifiers` = 同集（无用户定制，spec FR-015c/Q3）。
- 每项必须提供：主形态（按钮）、`menuFormRepresentation`（溢出/菜单形态，与主形态**同一动作**）、`toolTip`、`accessibilityLabel`；Pin 额外提供 `accessibilityValue`（开/关）且溢出形态为带 state 的 toggle。
- 优先级固定：Pin = `.high`；其余 = `.standard`（spec FR-015a；R7 预留仅一个常量的回退）。
- 项对象在控制器生命周期内缓存，不随缩放重建。

## 3. `AppearancePanelView` ↔ host

- 输入：`note` 外观字段（只读初始）；输出：`onAppearanceChange(Note)` 闭包（面板合成修改后的 Note 副本）→ 调用方执行 `host.updateAppearance` + `updateNotePaper`（即时预览，spec FR-008）。
- 数值契约：透明度 Slider 值域 0.40–1.00、步长 0.05；显示"NN%"（spec FR-009，禁止截断）。
- 重置语义：`NotePalette` 默认键 + `transparency = 1.0`（spec FR-008"恢复合理默认"）。
- 颜色选择：7 键调色板 + custom（既有 `paletteStorage` 映射逐字保留）；选中态=勾选+名称+色块（001 FR-044）。

## 4. `EditorSelectionBridge` ↔ `RichTextView`

- `RichTextView.Coordinator` 新增（契约语义）：
  - 选区/焦点变化回调：`onSelectionChange(isTextSelected:hasFocus:selectionRectInWindow:...)`；
  - 选区矩形：NSTextView 坐标系 → 窗口坐标（供上下文行定位，plan §4.4）；
  - 格式写操作：`applyMarks(_:)`（bold/italic/underline/strikethrough/inlineCode）作用于选区或 typingAttributes；无选区路径（作用于后续输入）；
  - IME 守卫：`hasMarkedText()` 期间不发布选区/不应用格式（复用既有模式）；
  - 窗口 key-state 变化（`NSWindow.didResignKey`/`didBecomeKey`）时重发布选区快照：`hasFocus` 随 `isKeyWindow` 更新（004 FR-012 失活隐藏语义——上下文格式化行在窗口失活时隐藏、重新激活且选区仍在时恢复；RichTextView.Coordinator 观察者随窗口变更/释放清理）。
- 桥只读投影：SwiftUI 侧不持有文本/标记副本；不反向写回 document。

## 5. 插入目标解析契约

- 入口：所有窗口级插入动作（工具栏菜单、应用菜单、`BlockInsertionControl`）最终调 host 插入方法，统一携带解析后的目标上下文：
  - `.caretSplit(richTextBlockId:offset:)`：富文本块光标处拆分（保留 run 属性），新块以中间 `sortKey` 插入；
  - `.afterBlock(blockId:)`：特殊块焦点上下文；
  - `.append`：无活动插入点（默认，等于既有 `max+1024` 行为）。
- 异步流程（截图/文件选择）在发起时快照目标上下文；完成后按快照落位，失效则降级 `.append`。
- `BlockInsertionControl`（空间上下文路径）与窗口级 Insert（命令式）共用同一 host 方法与目标解析（spec FR-010/Q4，避免两套插入系统）。

## 6. 窗口标题派生契约

- `deriveWindowTitle(noteTitle:firstLine:)`：见 [data-model.md](../data-model.md) §4.1。
- 同步时机：打开时；`Note.title` 变化时；无标题笔记的内容首行变化时（blocks 变化触发，字符串级节流）。
- 方向：仅 host→window；标题栏不写回（编辑在内容顶部标题框，spec FR-003/澄清决策）。

## 7. 窗口生命周期契约（修复项）

- 任何关闭路径（红绿灯/⌘W/`closeAll`/菜单）最终必须：保存帧 → `NoteWindowBridge.unregister` → 释放 toolbar 控制器 + delegate + host（`close()` flush + FR-012a）。
- 关闭后 `isOpen(noteId:)` 必须为 false；再次 `open` 走全新创建路径（不再复活死 host 窗口）。
- `toggleNoteWindows` 使用 `NoteWindowBridge.allRegistrations()`（不再按 title 过滤）。
