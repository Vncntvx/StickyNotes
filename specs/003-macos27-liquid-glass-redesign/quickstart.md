# Quickstart: macOS 27 原生质感重设计（Liquid Glass）验证指南

**Feature**: `003-macos27-liquid-glass-redesign` | **Date**: 2026-08-09

## 前置条件（构建/测试）

本机 Xcode 27 beta（27A5228h）已安装，但系统 `xcode-select` 指向 CLT（缺 `Testing.framework`）。所有命令**必须**前缀：

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

CI 目标工具链为 Xcode 26.x / Swift 6.3 / macOS 26.0 部署目标（见 `Documentation/toolchain.md`）；本机新于 CI，所有新 API 使用必须带可用性守卫并记录到 toolchain.md。

## 基线验证（Phase 0 之后必须全绿）

```bash
# StickyCore 全部测试（8 目标 92 套件）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore

# App 构建（无签名）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO

# AppTests + AppUITests（44 + 5 套件；UI 测试需交互桌面会话）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'
```

## 分阶段人工验证场景

### Phase 1（呈现基础）
- 浅色/深色模式下七色调色板（黄/桃/粉/绿/蓝/薰衣草/灰）各自渲染正确、文本对比达标；旧紫色笔记显示为薰衣草；自定义颜色原值不变。
- 新菜单栏命令可用（File/Edit/View/Window/Help），Quit/Help/About/Settings 不依赖 Library footer。

### Phase 2（Library）
- 单一原生工具栏（新建、搜索、排序、Notes/Trash 目的地）；无底部栏、无 Quit 入口。
- 窗口宽度 320–1600 pt 缩放：列数按 `max(1, floor((w+12)/192))` 确定性变化；SC-021 断点（≥756→4 列、≥564→3、≥372→2、以下 1）；卡片高度 72–128 pt、空白占比 ≤20%（SC-022）。
- 搜索为原生搜索体验（清空/退出行为）；"Search All Notes" 全局快捷键聚焦 Library 搜索框。
- 移入 Trash 无确认；Trash 内"永久删除"/"清空 Trash"有显式确认（FR-026）。
- 键盘：方向键选择 + Return 打开 + ⌘⌫ 移入 Trash。

### Phase 3（笔记窗口）
- 新建即获焦可打字（SC-003）；"Add Block" 首屏常驻控件不存在；块插入经插入点上下文控件 + 菜单/键盘命令可达（SC-004）。
- 窗口失活后重激活：强调色/浮动控件呈现 macOS 失活外观（FR-045）。

### Phase 4（设置）
- 设置窗口为原生工具栏式标签导航（通用/同步/字体/权限），面板高度适配内容（SC-011）。
- 字体面板呈现单一"笔记字体"概念 + 中英文混排实时预览；存储键不变。
- 快捷键录制：冲突报错不静默替换；可重置/清除。

### Phase 5（同步 UX）
- 正常同步零占位；人为断网/改密码/删远程仓库，验证七类状态横幅（三要素 + 重试/动作）、无内部错误标识符（FR-011/SC-012）。
- 高级区包含：替换仓库/移除配置/加入既有 vault（恢复重入）/导出同步配置/导出诊断包；破坏性操作有确认（FR-054）。

### Phase 6（macOS 27 精修）
- Reduce Transparency / Reduce Motion / Increase Contrast / Show Borders 下自定义控件可理解（SC-015）；玻璃仅存在于功能/控制层（SC-010/SC-019）；无手工模糊/渐变仿制。

### Phase 7（QA 与迁移验证）
- 旧数据/旧仓库夹具（001 fixtures + 真实旧 vault）升级后全部有效（SC-020/SC-025）；加密语义与仓库格式不变。

## 实施验证记录（2026-08-09，/speckit.implement 完成）

- **自动化全绿**：StickyCore 605 测试（7 模块）、AppTests 242 测试（53 套件）0 失败；Performance/Search/Keystroke 性能套件全绿（SC-024）。
- **T078 菜单栏右键下拉菜单**：已实现（专用 `NSStatusItem` 菜单，`MenuBarDropdownMenu.swift`；右键/⌥-点击呈现 打开 Library/设置/帮助/关于/退出，左键仍开 Library 窗口），构建绿。
- **AppUITests**：2026-08-09 产品决策——**取消全部自动化点击测试**（macOS 27 beta headless 会话下不可靠）；`AppUITests/CriticalFlowsUITests.swift` 仅保留无点击启动冒烟测试，交互旅程改由人工 QA 覆盖（详情见 001 history/tasks-log.md 2026-08-09 条目）。
- **手动视觉 QA 矩阵（T074/T079）**：浅/深、激活/失活、系统强调色、Reduce Transparency/Motion、Increase Contrast/Show Borders、显示比例、320pt 与宽 Library、紧凑笔记窗口、多窗口、纯键盘、VoiceOver —— **待人工执行（T079 已登记延期，需交互桌面会话；本会话 MenuBarExtra 窗口无法经合成点击呈现，验证过 deep-link 窗口路径可用）**。SC-018 HIG 走查清单条目逐面登记于该行后续人工执行。
- **迁移验证（US7）**：001 旧六色/自定义颜色/Trash 笔记/窗口帧/快捷键/字体偏好夹具全过（T068-T070）。

## 验收驱动

- 关键验收映射见 `spec.md` 各 User Story Acceptance Scenarios 与 Success Criteria SC-001..SC-025。
- 性能回归：`PerformanceBaselineTests`、`SearchPerformanceTests`、`KeystrokeLatencyTests`（SC-024）。
- 手动视觉 QA 矩阵见 `plan.md` 第 12 节（浅/深、激活/失活、强调色、显示比例、窄/宽窗口、紧凑笔记窗口、多窗口、纯键盘、VoiceOver）。
