# Quickstart: 独立笔记窗口原生镀铬与自适应重设计 — 验证指南

**Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

本指南是 /speckit.plan 交付的验证/运行手册（非实现说明）。实现细节见 tasks.md（Phase 2 输出）。

## 0. 环境（AGENTS.md 强制）

- 本机工具链：Xcode 27 beta（27A5228h）位于 `/Applications/Xcode-beta.app`；系统 `xcode-select` 指向 CLT（缺 Testing.framework）。**所有构建/测试命令必须前缀** `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。
- CI 目标：Xcode 26.x / macOS 26 SDK / Swift 6.3。任何 macOS 27 专属 API 必须 `#available` 守卫，保证 26 SDK 可编译。
- 部署最低：macOS 26（不得更改）。

## 1. 构建与测试命令

```bash
# StickyCore 包（无改动预期，回归用）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore

# App 目标构建
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO

# App 测试套件
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'

# 本机手动运行（稳定签名身份，避免每次重签提示）
./scripts/sign-local.sh   # 或 IDENTITY=... ./scripts/sign-local.sh
```

**每阶段验收门槛**：除本特性明确新增/翻转的测试外，既有套件全绿；本命令运行 0 错误。

## 2. 关键测试文件（实现时新增/修改）

| 文件 | 覆盖 |
|---|---|
| `AppTests/NoteWindowLifecycleTests.swift`（改） | minSize 320×140（Q6）、titleVisibility 隐藏 + window.title 派生（Q7）、红绿灯关闭→`isOpen == false`（反注册）、fullSizeContentView 转绿、帧恢复 |
| `AppTests/TitleDerivationTests.swift`（新） | 手动标题/首行/空兜底/长输入 |
| `AppTests/InsertionTargetingTests.swift`（新） | 光标拆分（属性保留）、特殊块后、追加降级 |
| `AppTests/FormattingRoundTripTests.swift`（新） | 标记应用→canonical 往返、typingAttributes 无选区路径 |
| `AppTests/AppearancePanelStateTests.swift`（新） | 透明度 clamp/步进、"NN%" 格式、重置 |
| `AppTests/NoteToolbarStateTests.swift`（新） | 工具栏项状态同步、溢出菜单 state、优先级映射 |
| `AppTests/MenuChecklistTests.swift`（改） | 新菜单条目（Format 组、View 置顶、插入图片） |

## 3. 手动验证场景（每个实现阶段走查）

### 3.1 窗口镀铬与标题（Phase 2 起）

1. 打开一条有标题笔记 → 内容顶部首行显示该标题（唯一可见标题，加粗加大与正文区分）；无标题笔记 → 标题框空（灰色占位「标题」）；标题栏始终无标题文本；Mission Control/窗口菜单中窗口名为派生标题。
2. 编辑内容顶部标题框 → 所见即所得；清空 → 回退灰色占位（`window.title` 回退首行/兜底，隐藏）。
3. 标题与正文共用同一条左边线（无水平错位）；标题→正文垂直间距紧凑（便签感，非文章编辑器式大间距）。
3. 红绿灯关闭 → 窗口消失；从 Library 重新打开 → 全新窗口且帧位置/尺寸恢复（`windowState` 表）。
4. 关闭后 ⌘W 或再次打开 → 无"复活死窗口"（旧缺陷）：置顶/外观仍生效。
5. 标题栏区域：笔记颜色透过工具栏玻璃（透明度 100% 与 <100% 都无接缝）。

### 3.2 宽度矩阵（Phase 6 全量；Phase 2 起粗检）

从 320 pt 连续拖到 2000+ pt 再拖回，在每个宽度**逐项**检查：

> 宽度矩阵以 plan.md §9.1 为单一来源；本表为执行快照，冲突时以 plan.md 为准。

| 宽度 | 直接可见 | 溢出 | 标题 | 编辑器 |
|---|---|---|---|---|
| 320（最小，Q6） | Pin+chevron | 外观/插入/更多 | 内容首行（行内截断） | ~280 pt 可用，可打字 |
| 480 / 640 / 800 / 1200 / 2000+ | 按 plan §9.1 矩阵 | — | 内容首行 | 无居中列、无水平裁剪 |

全局不变量（任何宽度）：无重叠/无裁剪/无"10…"式截断/无换行/无图标残留/Pin 切换零位移/透明度面板数值完整/滚动条不抢空间/缩放不重置工具栏状态/标题始终在内容首行（标题栏无标题文本，Q7）。**连续拖拽**（非仅静态截图）是强制验收动作。

### 3.3 功能走查

1. **置顶**：工具栏 Pin 开关 → 窗口浮于其他应用之上；状态图标+tooltip+VoiceOver value 同步；溢出菜单中为带勾选 toggle；View 菜单 "Always on Top" 同效；重启应用后按笔记保持（DB）。
2. **外观**：Appearance → popover：7 色（含 custom 逐字保留）、透明度 Slider 40–100% 步 5、当前值 "NN%" 完整、改动即时预览、恢复默认=默认色+100%；点外/ESC 关闭。
3. **插入**：Insert 下拉菜单——截图（区域/窗口）、文件引用、**图片**（新，相册/文件面板）、待办、代码块。验证落位：富文本光标处拆分插入（标记保留）、Todo 输入框焦点时插其后、无焦点时追加末尾。编辑器内 `+` 控件（BlockInsertionControl）在悬停/选区时出现且动作同源。
4. **格式化**：选中文本 → 浮动玻璃行出现（B/I/U/删除线/代码/字号）；失焦/无选区 → 消失；Format 菜单始终可用（⌘B/⌘I/⌘U）；无选区时格式作用于后续输入；中文 IME 组合期间不触发。
5. **多窗口**：3+ 笔记不同宽度并存，各自独立缩放/置顶/外观；激活/失活呈现 macOS 默认区分，失活内容可读。

### 3.4 无障碍与系统模式

- VoiceOver 走查：工具栏项标签/值、面板滑块与色板、溢出菜单。
- 纯键盘：Tab 进入工具栏与 chevron、⌥C/⌥O/⌥T 步进、⌘B/⌘I/⌘U、⌘W、⌘⌫。
- Reduce Transparency / Increase Contrast / Reduce Motion / 深色模式：功能与可读性完整（玻璃外观由系统降级）。

## 4. 视觉对比（Phase 7）——已取消

- ~~对当前 main 分支同一笔记在 320/480/640/800/1200/2000+ pt 各截一张基线图；本特性实现后同条件截图对比。~~
- ~~逐项评估（plan §9.4）：标题（内容首行）对齐、红绿灯原生性、工具栏密度、垂直镀铬高度（显著低于旧控件行）、编辑器起点与水平 inset、滚动条存在感、背景连续性、玻璃层级、激活/失活、宽窗行为。~~
- **2026-08-13 用户决策：截图对比流程取消。** 剩余人工验收 = §3.2 连续拖拽 + §3.1 标题单源观感。

## 5. 性能核查

- 连续拖拽缩放无卡顿（系统布局负责，无手动测量）。
- 缩放中不重建 NSTextView/块/工具栏对象图（控制器缓存项）。
- 打字/选区变化不触发工具栏整体重建（观察范围=外观字段+选区桥）。
- 空闲无持续 CPU（001 SC-006）。

## 6. 完成判定（对 spec 成功标准）

SC-001~016 逐一过检：320→2000+ 连贯观感；零畸形控件；溢出/菜单 100% 可达；标题（内容首行）与编辑器对齐一致；内容视觉主导；镀铬重量显著下降；无自定义关闭；颜色+透明度单一工作流；格式化不常驻；置顶易找且状态明显；相机/附件无需常驻按钮仍可达；原生观感；玻璃不压过内容；多窗口激活/失活正确；编辑/块/附件/截图/置顶/帧/生命周期无回归；响应式主要靠系统机制（代码审查：无新增手写断点）。
