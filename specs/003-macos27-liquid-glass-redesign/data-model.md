# Data Model: macOS 27 原生质感重设计（Liquid Glass）

**Feature**: `003-macos27-liquid-glass-redesign` | **Date**: 2026-08-09

## 数据层原则

本特性为**纯呈现层重设计**：不新增/删除任何本地数据库字段，不改变 001 schema（migrator v1/v2）、偏好键、同步契约（`specs/001-sticky-notes-app/contracts/` 全部 schema 不变）。以下实体均为**运行时呈现模型**，不入库、不同步（FR-090/Data & Migration Implications）。

## 呈现层实体

### NoteColorPaletteEntry（内置调色板条目）

- **来源**：应用内常量（`App/Sources/Features/DesignSystem/NotePalette.swift`），不入库。
- **字段**：
  - `colorKey: NoteColorKey`（Domain，身份；数据库存储值不变）
  - `lightColor: Color`（浅色模式设计值）
  - `darkColor: Color`（深色模式设计值）
  - `contrastValidated: Bool`（FR-031 阈值校验标记，测试断言用）
- **规则**：七色（黄/桃/粉/绿/蓝/薰衣草/灰）；浅/深两套为独立设计值，禁止机械透明度/亮度变换（FR-031）；迁移映射黄→黄、粉→粉、紫→薰衣草、蓝→蓝、绿→绿、灰→灰（FR-032）；自定义颜色原值保留、不走调色板。
- **约束**：所有组合满足 001 FR-042（主文本 ≥4.5:1、大文本/活动控件 ≥3:1，以真实渲染背景输入）；前景自动调整逻辑（`ReadableTheme.projecting`）改用调色板实际值。

### SyncStatusPresentation（同步状态呈现模型）

- **来源**：App 层（新文件 `App/Sources/Features/Library/SyncStatusPresentation.swift`），纯函数映射，无状态。
- **字段**：
  - `category: SyncStatusCategory`（七类：cannotConnect / authFailed / needsUnlock / pendingChanges / conflictCopiesCreated / historyAgedOut / repositoryDamaged）
  - `title: String`（zh-Hans/en 本地化）
  - `detail: String`（三要素：发生了什么 / 本地安全 / 可做什么）
  - `action: SyncStatusAction?`（retry / unlock / reauthenticate / viewConflicts / advancedRecovery / none；viewConflicts 打开既有冲突副本笔记窗口，001 语义）
  - `isDismissible: Bool`（FR-010 可关且状态不变不重现）
- **输入**：`SyncCoordinator` 暴露的状态 + `SyncSummary` 标志（`historyAgedOutDetected`、`conflictCopiesCreated`）+ `ProviderError.sanitizedCode`/`isTransient` + `StickyError` 类别。
- **测试**：每个内部错误代码 → 七类映射穷举（FR-012；无内部标识符泄漏断言，zh-Hans/en 齐全）。

### NoteCardPresentation（重设计后的卡片）

- **来源**：`CardProjection` 行（不变）+ 呈现规则常量。
- **字段**（沿用现有 `NoteCardRow` 语义，呈现规则变化）：
  - title / summary / 2 行预览 / 相对≤7 天转绝对时间 / 颜色（调色板值）/ 待办进度 / 封面缩略图 / 警示标识——均沿用 001 FR-020/020a/021/025。
  - 高度：内容驱动，72–128 pt 界（SC-022）；宽度 180–228 pt 公式（FR-021）。
- **新增呈现规则**：密度常量入 DesignSystem（`NoteCardMetrics`：minWidth 180、spacing 12、columnFormula、heightBounds）。

### ~~ShortcutBinding（快捷键条目）~~ — REMOVED 2026-08-10

全局快捷键随 001 FR-120/FR-121 移除：`LocalPreferences.globalShortcuts.<action>` 键、录制器 UI 状态与"原生快捷键偏好形态"呈现不再存在（已删除，不再迁移）。

### WindowPresentation（窗口呈现配置）

- **来源**：应用内常量 + 既有 `WindowState` 持久化（不变）。
- **字段**：Library 工具栏项集合与溢出策略、设置窗口尺寸（内容适配 FR-051）、About/Help 尺寸（contentSize）。
- **不变**：笔记窗口帧/首选显示器持久化（`SQLiteWindowStateRepository`）、菜单栏定位（`MenuBarWindowFrame`）。

## 状态流转（仅呈现层）

- **同步状态横幅**：`none（零占位）⇄ 七类注意态`；关闭后状态不变不重现，新错误类别重现（FR-010）。
- **卡片选择**：单击选择 / 双击打开 / 方向键移动 + Return 打开 + ⌘⌫ 移入 Trash（FR-024）；选择态不以颜色为唯一传达（FR-023/044）。
- **Trash 确认**：移入 Trash 无确认；永久删除（单条 + 清空）显式确认（FR-026）。

## 迁移清单（无）

| 持久化项 | 现状 | 新格式 | 迁移 | 说明 |
|---|---|---|---|---|
| note/blocks/todos/assets/tombstones | v1/v2 schema | 不变 | 无 | FR-090 |
| colorKey/customColor | 六色 + custom | 不变（身份值） | 无 | 调色板是呈现映射 |
| 偏好（快捷键/字体/同步策略/Dock/记忆解锁） | 既有键 | 不变 | 无 | 键名不动；呈现变 |
| 同步配置/vault/Keychain | 既有 | 不变 | 无 | FR-090/151/154 语义不变 |
| 窗口状态 | 既有 | 不变 | 无 | FR-032/033 |
