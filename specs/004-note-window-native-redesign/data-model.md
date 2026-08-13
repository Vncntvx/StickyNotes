# Data Model: 独立笔记窗口原生镀铬与自适应重设计

**Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## 1. 持久化层（无变更）

本特性**不新增、不修改任何持久化实体或字段**。沿用既有（001/003 已交付）：

- **Note**（`Packages/StickyCore/Sources/Domain/Models/Models.swift:20-124`，`notes` 表，GRDB/WAL/FTS）：本特性使用字段 `title: String?`、`colorKey: NoteColorKey`、`customColor: String?`、`transparency: Double`（0.00–1.00/0.05，语义=透明度，004 Q8）、`textSize: Int`（9–24）、`alwaysOnTop: Bool`（=置顶，DB 列）、`widgetEligible: Bool`。**置顶跨关闭/重启的持久化 = 既有 DB 语义，本特性不改**。
- **Block / TodoItem / RichTextDocument**：不变（块拆分仅改 `sortKey` 值，不改变 schema 或 payload 结构）。
- **WindowState / WindowFrame**（`windowState` 表，设备本地，永不同步）：帧持久化语义不变。
- 无偏好键变更；无迁移脚本。

## 2. 临时（内存）对象——非持久化

| 对象 | 生命周期 | 事实源关系 | 说明 |
|---|---|---|---|
| `NoteToolbarController`（新） | 窗口打开→关闭，与 `NoteWindowDelegate` 同生共死；由 `NoteWindowCoordinator.toolbars[noteId]` 强持有 | 状态读取源 = `NoteWindowHostModel.note`（只读观察）；动作源 = 协调器/host 方法 | 不持有独立状态副本；不持久化任何工具栏排列/弹出控件/上下文状态（spec FR-015c） |
| `AppearancePanelView` 状态 | popover 会话内 | 每次改动即 `updateAppearance`（即时预览） | 无持久化中间态；关闭即弃 |
| `EditorSelectionBridge`（新，@Observable） | 窗口打开→关闭 | NSTextView 选区/焦点快照（只读投影；含窗口 key-state 变化重发布，004 FR-012；2026-08-13 起跟踪**聚焦编辑器**——多块编辑器共用一个 bridge，格式命令路由到焦点所在块，FR-038） | 不写回编辑器；仅驱动 SwiftUI 上下文 UI 呈现 |
| `UndoManager`（每便签窗口一个，2026-08-13 新） | 窗口打开→关闭（`NoteWindowHostModel` 持有；`close()` 清栈断环） | 编辑历史权威：全部块编辑器经 `NSTextViewDelegate.undoManager(for:)` 共用；结构变更注册为单个撤销组（FR-037） | 模型推送用 `disableUndoRegistration` 包裹、不清栈；结构变更清空旧逐字撤销（已确认决策） |

## 3. 状态所有权与同步规则

- **标题**：持久化事实源 = `Note.title`；可见展示事实源 = 内容顶部首行标题框（可编辑、视觉区分，Apple Notes 模式 Q7）；`window.title` = 派生值（`Note.title ?? 内容首行 ?? 本地化兜底`），仅隐藏用途（Mission Control/窗口菜单/VoiceOver，titleVisibility 隐藏）。同步方向**仅 host→window**（协调器 `updateWindowTitle(noteId:)`；`NoteWindowContent.onChange` 触发；打开时设初值）。标题编辑写回 `Note.title`（空→nil），经既有 `updateAppearance` 持久化。
- **置顶**：行为事实源 = `WindowLevelBridge`/`NoteWindowBridge.applyCollectionBehavior`（唯一入口 `coordinator.updateAlwaysOnTop`）；持久化事实源 = `Note.alwaysOnTop`（DB）。工具栏按钮/溢出项/View 菜单三形态呈现同一状态，无第二状态副本。
- **文本与格式标记**：事实源 = NSTextView（textStorage/typingAttributes/selectedRange）；SwiftUI 只读投影（selection bridge）。格式写操作直改 NSTextView，经既有 canonicalDocument 往返（FR-053 标记集）。2026-08-13（FR-036/038/041/042）：全部含文本块（正文/todo/code）各承载一个 NSTextView 编辑面——todo 为富文本编辑面（run 标记保留）、code 为纯文本等宽编辑面；选区发布的光标偏移为 scalar（UTF-16 转换后）；完成态删除线/次要色为显示专用样式，不进 canonical 往返。
- **编辑历史（撤销/重做）**：事实源 = `NoteWindowHostModel.undoManager`（每窗口一个共享 NSUndoManager，FR-037）。结构变更（插入/删除/移动/勾选/空块移除）= 单个撤销组（恢复 blocks + TodoItem/FileLocator 持久化行）；逐字输入撤销由各块 NSTextView 经 delegate `undoManager(for:)` 落同一栈。
- **块与内容**：事实源 = `NoteWindowHostModel.blocks`（autosave 既有管线）。
- **外观（颜色/透明度/字号）**：事实源 = `Note` 外观字段；唯一写路径 = `NoteWindowHostModel.updateAppearance`（立即持久化 + FTS + sync）。

## 4. 纯函数（可单测，无 IO）

1. **`deriveWindowTitle(noteTitle:firstLine:) -> String`**：`noteTitle` 非空 → 原值；否则首行（去空白）；均空 → 本地化兜底"无标题笔记"。规格：spec FR-003、plan §3.4。
2. **`resolveInsertionTarget(blocks:selection:) -> InsertionTarget`**：`.caretSplit(blockId:offset:)` / `.afterBlock(blockId:)` / `.append`。规格：spec FR-010、plan §4.3。
3. **`splitRichTextBlock(payload:offset:) -> (leading: RichTextDocument, trailing: RichTextDocument)`**：保留 run 属性与标记；用于光标处块拆分。规格：plan §4.3、R3。
4. **`formatOpacityPercent(value: Double) -> String`**：`"NN%"` 完整数值，任何宽度不截断（spec FR-009）。
5. **`toolbarVisibilityPriority(itemIdentifier: String) -> NSToolbarItemVisibilityPriority`**：固定映射（Pin/Insert=`.high`，Appearance/More=`.standard`；T065，2026-08-13 窄窗口语义修订）。
6. **`scalarOffset(fromUTF16:in:) -> Int`**（2026-08-13 新）：NSTextView 的 UTF-16 码元偏移 → Unicode scalar 偏移（CJK/emoji 安全）。规格：spec FR-042。

## 5. 状态迁移

- 无数据迁移；唯一"状态迁移"是窗口生命周期修复：红绿灯关闭从"注册表残留 + host 释放"改为"反注册 + 释放"（行为对齐 ⌘W 路径）——spec 成功标准 15 的回归修复项，不涉及存储。

## 6. 校验规则（来自 spec）

- 透明度 clamp 0.00–1.00、步长 0.05（001 FR-041a 语义经 004 Q8 修订；spec FR-008/009）。
- 字号 clamp 9–24（001 FR-043a；spec FR-012）。
- 颜色：7 键调色板 + custom，既有值逐字保留（001 FR-032；spec FR-008）。
- 最小窗口：contentMinSize (320, 140)（spec FR-017a，Q6，2026-08-13 修订）。
- 对比度：custom+opacity 对合成背景的既有校验（`NoteAppearance.projecting`）沿用；窗口背景统一透明度后需复检（plan §4.2）。
