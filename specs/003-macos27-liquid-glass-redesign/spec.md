# Feature Specification: macOS 27 原生质感重设计（Liquid Glass）

**Feature Branch**: `003-macos27-liquid-glass-redesign`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Redesign and refine the existing native macOS Sticky Notes application so that it feels like a first-party-quality macOS 27 app while preserving its current product capabilities and lightweight sticky-note identity. This is primarily a UX, interaction, information-hierarchy, and visual-system redesign. Do not turn the product into a generic document editor, dashboard, or iPad-style app. The core experience must remain: create a note immediately, see all notes at a glance, open a note in its own lightweight window, write with almost no UI friction, and optionally synchronize notes securely. The redesign must follow the current Apple Human Interface Guidelines for macOS 27 and the current Liquid Glass design language. Liquid Glass must be treated as a functional layer for navigation and controls, not as decoration and not as the material for note content itself. The yellow or colored sticky-note surface is content and must remain visually distinct, calm, readable, and primarily opaque. Prefer native macOS controls and behaviors wherever possible so that the system provides the correct appearance, pointer behavior, active/inactive states, accessibility response, Dark Mode behavior, and future Liquid Glass refinements automatically. Goals: (1) feel unmistakably native to macOS 27; (2) reduce visible UI chrome; (3) make notes, rather than controls, the visual focus; (4) coherent visual language across Library, Note windows, Settings, Trash, search, sync status, permissions; (5) Liquid Glass deliberately for the functional/control layer, note content paper-like and stable; (6) improve information density without busyness; (7) preserve fast keyboard-driven workflows and precise pointer interaction; (8) preserve existing user data, note behavior, sync functionality, global shortcuts, permissions, editing capabilities unless explicitly changed; (9) support Light/Dark Mode, system accent colors, active/inactive windows, Reduce Transparency, Reduce Motion, Increased Contrast/Show Borders, keyboard navigation, VoiceOver; (10) avoid decorative effects that only demonstrate Liquid Glass. Product character: lightweight, calm, immediate, tactile without skeuomorphism, native, content-first, suitable for long open periods, visually quieter. Library window: single native macOS window toolbar; New Note as a native toolbar action, fast and discoverable; search as native macOS search in the toolbar; sorting secondary; Notes and Trash as navigation destinations (collapsible sidebar per macOS behavior, or a compact toolbar treatment — prefer the simpler native solution for two destinations); remove the permanent bottom utility bar (Sync Issue, Retry, refresh, help, info, settings, Quit); Quit never in application UI; Help/About/Settings/refresh/diagnostics in conventional macOS locations. Sync status: no permanent footer on success; contextual status only when attention is needed, explaining what happened, that notes remain safely available locally, and the action to take; clear retry/recovery action; no internal error identifiers such as 'sync.historyAgedOut' in normal UI; diagnostics only via advanced/exported diagnostic experience. Note grid and cards: substantially denser cards; adaptive grid on resize; card communicates in decreasing priority: title or first meaningful line, short preview, modification time; avoid large unused areas; cards preserve note color identity but are not Liquid Glass (content layer); restrained distinction via native-looking borders, subtle depth, selection treatment, spacing, hover; no exaggerated shadows/gradients/gloss/textures; obvious-but-understated selection not relying on color alone; hover actions must not make layout jump; support single-click selection, double-click open, contextual menu, keyboard navigation, delete/move to Trash, drag if already supported. Note colors: introduce a restrained palette (minimum: yellow, peach, pink, green/mint, blue, lavender, neutral/gray); color identifies the note without reducing text contrast; Light and Dark Mode each have intentionally designed note colors, not mechanical opacity of the same RGB; sufficient contrast for primary/secondary text, selection, controls. Individual sticky note window: preserve standard macOS window behavior and traffic-light controls; content area feels like the note itself, not an editor in large chrome; new note places visual/keyboard focus near the top immediately, no large unexplained empty vertical region; extremely low-friction writing (create and type immediately, no block-type choice); the permanently visible 'Add Block' control is too dominant — block insertion becomes contextual (subtle add control, contextual control near insertion point, '/' keyboard mechanism, native menu/command); block functionality not removed, only its visual priority reduced; note surface remains content, not glass; floating controls may use native Liquid Glass when appropriate, appear only when useful, never permanently obscure content; usable in active and inactive states with expected macOS inactive appearance. Settings: native macOS Settings window (not web-style form); keep General/Sync/Fonts/Permissions; replace oversized custom segmented navigation with native Settings navigation; native form conventions (alignment, spacing, controls, dividers, labels, explanatory text, grouping); no large rounded gray rectangles around every section; no fixed-height panes with hundreds of pixels of empty space. General: preserve Show icon in Dock and all global shortcuts (Open/Close Library, New Blank Note, Capture Region into New Note, Capture Window into New Note, New Note from Clipboard, Search All Notes, Show/Hide Note Windows); native shortcut preference interface with current values, recording state, reset, conflict/error feedback. Sync Settings: preserve encrypted single-repository sync model and provider functionality; default Sync page focuses on sync status, provider, last successful sync, automatic sync, sync frequency, whether the local vault remains unlocked on this Mac, primary sync/retry action; internal errors translated to human-readable descriptions and recovery actions; Replace Repository, Remove Configuration, Export Sync Profile, Export Diagnostic Bundle moved to an Advanced/separate management area; destructive actions visually/semantically distinguished with confirmation; the encrypted-notes-unrecoverable warning kept but in standard warning treatment, concise, not dominating the pane. Fonts: keep customization useful to ordinary users; user-facing concept of a primary Note Font with appropriate system fallback rather than implementation typography terms; Chinese and Latin render naturally together; default aligns with macOS system typography; meaningful multilingual live preview. Permissions: keep permissions lazy (ask only when a related capability actually needs it); Settings clearly displays current state, why needed, the dependent feature, and an action to open/initiate the system permission flow; never imply a permission is mandatory when the feature is unused. Liquid Glass design requirements: glass is the functional layer (controls and navigation); note content, cards, editor surfaces, content backgrounds must not be glass; prefer system-provided controls/toolbars/menus/search/sidebars/forms/buttons/popovers/navigation; custom glass only for genuinely custom interactive controls; no nested glass-on-glass; no glass as decoration; prefer regular glass where legibility matters; clear glass only over visually rich content where seeing content is the goal, not the default; interactive glass limited to interactive controls; related custom glass controls behave as a coherent group, not unrelated floating pills; toolbar controls group/separate/overflow by width; important actions remain as the window narrows, secondary actions move into system overflow; content may continue beneath native toolbar/sidebar glass; never manually reproduce Liquid Glass with blur/opacity/gradients/borders/shaders when a system behavior exists. macOS 27 system behavior: correct with Liquid Glass appearance, Light/Dark, system accent, active/inactive windows, Increase Contrast/Show Borders, Reduce Transparency, Reduce Motion, keyboard-only, VoiceOver, different display scales, narrow and wide resizable windows; custom controls remain understandable without transparency/animation; typography/colors/icons/hit targets legible without translucency; SF Symbols and standard macOS iconography. Window and resizing: first-class behavior; wide windows more columns, narrow fewer; secondary toolbar controls to overflow rather than compressing content; navigation adapts without duplicating controls; cards keep readable dimensions; note windows useful at compact sizes without unnecessary toolbars. Keyboard/menus/conventions: every important toolbar command also has a menu-bar command; preserve and improve global shortcuts; familiar local shortcuts; avoid invented conventions when macOS has a standard equivalent; context menus expose useful note actions without duplicating the entire application menu. Visual system: coherent system for spacing, typography, note colors, corner radii, selection, focus, borders, separators, hover, pressed, disabled, active/inactive, semantic warning/error/success; use macOS system metrics rather than arbitrarily large padding/radii; fewer visible containers — grouping via alignment, spacing, hierarchy, separators, standard form/list behavior before rounded background panels; Library, Settings, Note windows clearly belong to the same product. Migration/compatibility: evolution, not rewrite; existing notes, deleted notes, colors where already stored, sync configuration, encrypted data, shortcuts, fonts, permissions, preferences must remain valid; no user loses note content or configuration; encryption semantics and repository format unchanged. Success criteria: 20 listed criteria (content-first Library, one-action creation, immediate typing, 'Add Block' no longer dominant, no permanent bottom bar, Trash secondary, native toolbar search, dense adaptive cards, non-glass cards, glass only in navigation/controls, no oversized Settings canvases, human-readable sync errors, advanced sync actions separated, Light/Dark correct, Reduce Transparency/Motion/Increase Contrast understandable, correct inactive states, pointer+keyboard reachability, feels like native macOS 27 not iPad/web/custom imitation, no handcrafted glass simulation, no data/config loss). Platform design constraint: implementation planning must target the current macOS 27 SDK and verify platform APIs against current Apple documentation before use; may rely on current real public Apple APIs such as SwiftUI glassEffect(_:in:), Glass, Glass.regular/clear/identity, Glass.tint(_:), Glass.interactive(_:), GlassEffectContainer, glassEffectID(_:in:), glassEffectTransition(_:), glassEffectUnion(id:namespace:), toolbar(content:), sharedBackgroundVisibility(_:), visibilityPriority(_:), EnvironmentValues.appearsActive, accessibilityShowBorders, accessibilityReduceTransparency, accessibilityReduceMotion; AppKit (only where genuinely needed): NSGlassEffectView, NSGlassEffectContainerView, effectIsInteractive, tintColor, cornerRadius, NSButton.BezelStyle.glass, NSBackgroundExtensionView, NSToolbar; do not invent API names/modifiers/materials/environment keys/compatibility flags; if any listed API changed, is beta-only, or has different availability in the installed SDK, verify against the installed macOS 27 SDK and current Apple documentation and use the documented equivalent; do not silently substitute a custom visual imitation. The specification should define user stories, requirements, edge cases, accessibility expectations, migration expectations, and measurable acceptance criteria for this redesign; it should not prescribe an unnecessary architectural rewrite."

## Clarifications

### Session 2026-08-09

- Q: 同步需要用户注意时，界面应区分呈现哪些状态类别？ → A: 按用户所需动作分组为七类可读状态，不平铺引擎内部全部分类（Option B）：①无法连接仓库（离线/仓库不可达，提供重试）②认证失败（需重新验证凭据）③需要解锁（需输入同步密码）④有未同步更改（信息性，可手动同步）⑤已创建冲突副本（提示并可查看）⑥同步历史已过期（仅告知，本地内容安全、无需强制动作，001 FR-174 语义）⑦仓库损坏/不兼容（需高级处理：替换或重新加入）。
- Q: 块插入应采用哪些上下文途径，"/"命令是否应成为真实的用户工作流？ → A: 采用"插入点附近的微妙添加控件 + 原生菜单/键盘命令"组合；不引入 "/" 命令系统（Option A）。
- Q: 从 Trash 中永久删除单条笔记，以及移入 Trash，各需要什么级别的确认？ → A: 移入 Trash 无需确认（30 天可恢复期即撤销机制）；永久删除（单条 + 清空 Trash）均需显式确认；不新增 Undo 命令（Option A）。
- Q: "加入既有仓库/保险库"在重设计后的同步设置中应属于哪一位置？ → A: 作为首次配置流程（初始设置），并在高级恢复区提供重入入口；日常切换仓库走"替换仓库"（001 FR-154 确认语义）；不将其变为日常动作（Option D）。
- Q: 设置窗口的四个面板应采用哪种原生 macOS 导航模式？ → A: System Settings 风格的工具栏式标签导航；不采用侧边栏或单面板滚动（Option A）。
- Q: 设置窗口的导航层级与窗口 shell（2026-08-14 Rev 2）？ → A: 逻辑区域改为通用 / 同步 / 隐私三个；字体并入通用面板 Notes 分区（FR-055）；权限面板更名为隐私面板（FR-056 修订）；窗口 shell 必须稳定（FR-051 修订）：切分区不改 geometry、最小宽度保证一级导航不折叠、Sync 溢出在内容区滚动；尺寸数值归实现层 SettingsWindowPolicy。
- Q: 菜单栏图标左键点击时，是保持"直接打开 Library 窗口"还是改为"弹出下拉菜单"？ → A: 左键直接打开 Library 窗口（FR-001 语义不变）；右键/⌥-点击弹出下拉菜单（打开 Library/设置/帮助/关于/退出），为 Dock 隐藏时 Constitution X 可达性载体（Option A）。

### Session 2026-08-14（UI 语义与信息架构重构批）

- Q: 搜索控件在 MenuBarExtra(.window) 无原生工具栏的前提下应如何实现？ → A: 采用原生 `NSSearchField`（NSViewRepresentable 桥接），替换手绘 TextField + quaternary 圆角背景；保留 searchQuery 状态与 ⌘F 聚焦契约（FR-003 修订：T018 结论后搜索栏落在顶部单一控制行内，控件本身必须是 AppKit 原生搜索控件）。
- Q: vault 锁定态是否应禁用"周期同步"配置？ → A: 锁定态豁免——schedule（Periodic sync）是设备本地偏好（001 FR-152），锁定下仍可配置，仅自动同步总开关关闭时禁用；锁定 caption 改为 "Unlock the vault to sync manually or resume automatic sync." 并保留本地笔记仍可用条款（FR-053 修订：禁用不可执行控件的范围收窄为真正不可执行的控件）。
- Q: 同步设置维护操作如何重组（FR-054 修订）？ → A: Storage 区新增 "Manage…" 菜单承载 Join Another Vault… 与 Set Up New Storage Location…（独立动作不合并流程，首配双入口保留，重入入口随 Manage… 移至 Storage）；Recovery 信息行移入 Security 分区（FR-163 标准样式语义不变）；Advanced 仅保留技术性操作（Vault ID / Export Sync Profile… / Export Diagnostic Bundle…）；Disconnect Sync… 移出 Advanced，为表单底部独立破坏性入口（确认语义不变）。
- Q: "笔记字体"设置的名称与生效范围（FR-055 修订）？ → A: 改名 "Note body font"（正文字体）——仅编辑器正文与卡片正文预览生效，标题保持系统 headline（信息层级）；卡片正文预览跟随用户字体（字号仍用卡片预览字号、2 行截断不变）；预览改为多行样本并真实应用 Text Spacing 的 lineSpacing（间距属呈现层，001 FR-043 语义不变）。
- Q: 补齐哪些菜单命令（FR-072/SC-017）？ → A: 新增 Restore、Empty Trash…、Sync Now 三条菜单栏命令（File 区，无自定义快捷键）；Empty Trash… 菜单命令与 Library ⋯ 菜单共用同一模型层确认机制（FR-026 确认语义不变）。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 内容优先的 Library（P1）

用户打开 Library 窗口，看到笔记卡片是绝对视觉主体；顶部只有一条安静的原生 macOS 工具栏：新建笔记、搜索、排序入口与导航目的地；底部不再有任何常驻工具条。

**Why this priority**: "打开 Library 即看到笔记"是本重设计的核心目标（目标 3、成功标准 1）。Library 是产品的第一表面，其信息层级决定整个产品的感知。

**Independent Test**: 打开 Library，验证窗口只有一条工具栏、无底部栏；笔记卡片占据内容区主体；用工具栏新建笔记、搜索、切换排序、进入 Trash 均可完成。

**Acceptance Scenarios**:

1. **Given** Library 窗口打开，**When** 用户观察窗口结构，**Then** 顶部只有一条原生 macOS 工具栏（新建、搜索、排序、导航目的地），**And** 不存在常驻底部工具条，**And** 界面中不存在任何"Quit"入口。
2. **Given** 任意数量的笔记，**When** 用户打开 Library，**Then** 笔记卡片网格是内容区的绝对主体，工具栏控件不占据超过一个原生工具栏高度的空间。
3. **Given** Library 工具栏，**When** 用户点击"新建笔记"工具栏按钮，**Then** 与使用 ⌘N 菜单命令创建的行为一致：新笔记窗口打开并获得键盘焦点（001 FR-007a）。
4. **Given** Library 工具栏，**When** 用户在原生搜索栏输入查询，**Then** 结果按 001 FR-024/FR-024a 的时效要求更新（见 FR-003），**And** 搜索栏视觉上属于工具栏（单一控制行，无第二行）。
5. **Given** 排序入口，**When** 用户更改排序，**Then** 支持 001 FR-022 的全部模式（最近修改、最近创建、标题、手动），**And** 排序控件的视觉权重不高于"新建笔记"与"搜索"。
6. **Given** Library 与 Trash 两个目的地，**When** 用户导航，**Then** 两者以紧凑的原生导航模式呈现（工具栏目的地控件或可折叠系统样式侧边栏），**And** Trash 不再占据 50% 宽度的顶层分段控件。
7. **Given** 应用已运行，**When** 用户左键点击菜单栏图标，**Then** 001 FR-001/FR-001a 的菜单栏附属定位行为保持不变（图标下方 4 pt、对齐图标左缘、完整可见屏内、无动画即时开合）；**Given** Dock 图标隐藏，**When** 用户右键（或 ⌥-点击）菜单栏图标，**Then** 弹出下拉菜单且包含 打开 Library / 设置 / 帮助 / 关于 / 退出 五项（FR-006/Constitution X）。

---

### User Story 2 - 即写即得的独立笔记窗口（P1）

用户从 Library 或快捷键新建笔记，焦点立即落在内容顶部，直接开始打字；"Add Block"不再是每个笔记中的第一个视觉元素；笔记表面是内容层（不透明、笔记色），浮动控件仅在有用时出现。

**Why this priority**: 独立笔记窗口是产品最重要的交互面（原描述）。低摩擦书写与"内容而非编辑器"的观感决定产品特质。

**Independent Test**: 新建笔记 → 直接打字无需选择块类型 → 验证块插入以"插入点附近控件 + 菜单/键盘命令"仍可访问 → 窗口失活后重激活验证外观状态正确。

**Acceptance Scenarios**:

1. **Given** 用户新建一条笔记，**When** 窗口打开，**Then** 键盘焦点立即位于笔记内容顶部附近，**And** 内容顶部与第一个文本之间不存在大段无解释的空白区域，**And** 用户无需选择块类型即可开始输入普通富文本。
2. **Given** 打开的笔记窗口，**When** 用户查看窗口外观，**Then** 窗口保留标准 macOS 窗口行为与标准红绿灯控件，**And** 内容区呈现为笔记本身（笔记色、不透明的内容表面，非玻璃材质），**And** 不存在将笔记包裹在大型应用外观中的视觉容器。
3. **Given** 笔记窗口，**When** 用户需要插入新块，**Then** 存在上下文插入途径：插入点附近的微妙添加控件与原生菜单/键盘命令，**And** "Add Block"不再作为每个笔记中的常驻首屏控件。
4. **Given** 笔记窗口中的全部块类型，**When** 用户插入富文本/待办/代码/文件引用/图片/截图块，**Then** 块功能与 001 FR-050 系列完全保留，仅呈现优先级降低。
5. **Given** 浮在笔记上方的控件（如颜色、添加、格式控件），**When** 它们出现，**Then** 使用当前原生 Liquid Glass 呈现（若为自定义交互控件），**And** 仅在有用时出现、可随指针离开隐藏、不永久遮挡笔记内容，**And** 窗口失活时控件与强调色呈现 macOS 预期的失活外观。
6. **Given** 窗口在激活与失活状态之间切换，**When** 用户比较两者，**Then** 失活状态不保留不恰当的强调色强调（遵循 macOS 失活窗口外观）。

---

### User Story 3 - 克制的笔记配色系统（P1）

用户为笔记选择一套和谐、可长期阅读的配色；浅色与深色模式下颜色各自经过设计；文本对比度始终达标。

**Why this priority**: 颜色是笔记身份的核心标识（001 FR-040），也是重设计视觉系统的一部分。浅/深色分别设计与对比度保证是宪法 X 的既有义务（001 FR-042），必须在本特性中落地为正式调色板。

**Independent Test**: 在浅色与深色模式下分别检查每个调色板颜色的主文本/次文本/选择态/控件对比度；将旧笔记颜色迁移后验证颜色身份保留。

**Acceptance Scenarios**:

1. **Given** 笔记颜色选择器，**When** 用户查看内置颜色，**Then** 提供克制的小调色板，至少包含：黄、桃、粉、绿/薄荷、蓝、薰衣草、中性灰七种。
2. **Given** 浅色模式，**When** 用户为笔记选择任一内置颜色，**Then** 颜色是为此模式专门设计的数值；**Given** 深色模式，**When** 选择同一颜色，**Then** 使用深色模式专用设计值，而非对同一 RGB 值做机械透明/亮度变换。
3. **Given** 任一内置颜色 + 任一外观模式，**When** 校验对比度，**Then** 主文本 ≥4.5:1、大文本与活动控件 ≥3:1（001 FR-042 阈值），次文本、选择态与控件同样达标。
4. **Given** 迁移前的旧笔记（001 FR-040a 六色），**When** 应用升级到新配色系统，**Then** 每条笔记的颜色身份按语义映射保留（黄→黄、粉→粉、紫→薰衣草、蓝→蓝、绿→绿、灰→灰），**And** 自定义颜色原样保留。
5. **Given** 用户先前选择的自定义颜色，**When** 应用升级，**Then** 自定义颜色值保持不变且继续可用（001 FR-040 保留）。

---

### User Story 4 - 原生质感的设置窗口（P2）

用户在设置中配置通用（含 Dock 开关与正文字体 Notes 分区）、同步（含人性化错误与高级区）、隐私（懒请求与状态展示）——整体呈现为原生 macOS Settings 窗口而非网页式表单。

**Why this priority**: 设置是"第一方质感"的可感知组成部分（目标 1/4/5）。同步与权限的正确呈现直接影响信任（目标 7）。

**Independent Test**: 打开设置，验证原生导航与表单规范；在三个面板间切换并验证窗口 geometry 稳定；查看同步状态与高级区；检查字体预览的中英文渲染；检查隐私面板权限状态展示。

**Acceptance Scenarios**:

1. **Given** 设置窗口，**When** 用户查看导航，**Then** 使用原生 macOS Settings 工具栏式标签导航（替代大尺寸自定义分段控件），**And** 包含"通用 / 同步 / 隐私"三个逻辑区域（2026-08-14 Rev 2）。
2. **Given** 任一设置面板，**When** 用户查看布局，**Then** 遵循原生表单惯例（对齐、间距、控件、分隔线、标签、说明文字、分组），**And** 不使用大圆角灰矩形包裹每个分区，**And** 窗口尺寸稳定：切换分区不改变 geometry、窗口不得缩窄至导航折叠、Sync 内容溢出在内容区滚动（2026-08-14 Rev 2）。
3. **Given** "通用"面板，**When** 用户查看，**Then** 保留"显示 Dock 图标"开关（全局快捷键项已于 2026-08-10 随 001 FR-120/FR-121 移除，不再呈现）。
4. ~~**Given** "通用"面板的快捷键界面，**When** 用户录制快捷键，**Then** 呈现为原生 macOS 快捷键偏好界面（当前值清晰可见、录制状态明确、可重置、冲突/错误反馈），**And** 冲突检测遵循 001 FR-121（不静默替换既有系统或应用快捷键）。~~ **REMOVED 2026-08-10**（全局快捷键已移除；原第 5–9 项顺延为 5–9）。
5. **Given"同步"面板，**When** 用户查看默认页面，**Then** 聚焦用户可理解的概念：同步状态（FR-012 分类映射，不用内部 Configured 状态）、存储位置、上次成功同步时间、自动同步开关、定期同步 Periodic sync（001 FR-152 选项保留：Off=仅变更后同步 / 每 5/15/30/60 分钟；2026-08-14 Rev 3 更名）、本 Mac 上 vault 是否保持解锁（001 FR-162a）、主同步/重试动作；vault 未解锁时如实显示锁定状态并禁用不可执行控件（2026-08-14 Rev 2；Rev 3：schedule 为设备本地偏好、锁定态仍可配置）。
6. **Given"同步"面板，**When** 用户查看高级区，**Then** "新建存储位置""断开同步""导出同步配置""导出诊断包"等维护操作位于独立的"高级"管理区，**And** "加入既有保险库"在已配置态保留独立恢复性入口，**And** 破坏性操作在视觉与语义上与常规操作区分并要求确认（001 FR-154 替换确认语义保留，2026-08-14 Rev 2）。
7. **Given"同步"面板，**When** 用户看到加密密码丢失警告，**Then** 采用标准警告样式、语言简洁（001 FR-163 语义保留），**And** 不占据整个面板。
8. **Given"通用"面板的 Notes 分区，**When** 用户设置"正文字体"（Note body font），**Then** 面向用户的概念为主字体 + 系统回退（不暴露实现性排版术语），**And** 提供中英文混排的多语言实时预览，**And** 默认值对齐 macOS 系统排版与回退行为（001 FR-043 行为保留，2026-08-14 Rev 2 由独立面板并入通用面板）。
9. **Given"隐私"面板，**When** 用户查看，**Then** 只展示有实际消费方的权限（屏幕录制）：当前状态、为何需要、依赖的功能、打开/发起系统权限流程的动作；状态 UI 不暴露公开 API 无法观测的区分；无消费方的权限（辅助功能）不出现以诱导预授权；请求时机保持懒请求（001 FR-131/132/133 保留，2026-08-14 Rev 2）。

---

### User Story 5 - 同步状态的上下文呈现（P2）

同步正常时 Library 不占任何常驻屏幕空间；需要用户注意时，出现简洁的上下文状态说明发生了什么、笔记在本地是否安全、可采取什么动作，并可直接重试。

**Why this priority**: 常驻同步状态消耗空间且制造焦虑；错误可读性直接关系用户对数据安全的信任（目标 12（同步信任）/13（数据安全），度量见 SC-012/SC-013/SC-020）。

**Independent Test**: 正常同步状态下无任何同步 UI；人为制造同步失败（断网/改密码），验证出现上下文状态条（含人话说明、本地安全声明、重试动作），且不出现内部错误标识符。

**Acceptance Scenarios**:

1. **Given** 同步正常工作，**When** 用户观察 Library，**Then** 不存在任何常驻同步状态页脚或指示器（正常同步不消耗持久屏幕空间）。
2. **Given** 同步需要用户注意（失败、需要操作），**When** 状态出现，**Then** 以简洁的上下文状态呈现（如就近横幅/内联），说明：发生了什么、笔记在本地仍然安全可用、用户可采取的动作，**And** 在适当时提供明确的重试/恢复动作。
3. **Given** 任一同步错误，**When** 呈现给用户，**Then** 普通界面中不出现内部错误标识符（如 "sync.historyAgedOut"），**And** 展示为本地化的可读描述与恢复动作（001 FR-180a 本地化）。
4. **Given** 需要诊断信息的用户，**When** 查看诊断，**Then** 内部标识符与诊断细节仅存在于高级诊断/导出诊断包体验中（001 FR-191 边界保留）。

---

### User Story 6 - 窗口缩放、键盘、菜单与系统行为（P2）

用户缩放 Library 与笔记窗口、只用键盘操作、在 Reduce Transparency / Reduce Motion / Increase Contrast / 键盘导航 / VoiceOver 下使用应用；Liquid Glass 只出现在功能/控制层。

**Why this priority**: 目标 9（系统行为合规）/10（显示比例）与"原生 macOS 27"的判定标准都建立在系统行为合规之上；缩放与键盘是日常 Mac 工作流（目标 7，度量见 SC-015/SC-018）。

**Independent Test**: 在 320 pt–1600 pt 宽度间缩放 Library，验证列数与溢出行为；仅用键盘完成新建/搜索/选择/打开/删除；开启 Reduce Transparency 与 Increase Contrast 验证自定义控件可读；用 VoiceOver 走查主要流程。

**Acceptance Scenarios**:

1. **Given** Library 窗口，**When** 用户从最窄到最宽缩放，**Then** 宽窗口显示更多笔记列、窄窗口渐进减少列，**And** 次要工具栏控件移入系统溢出行为（不压缩内容至不可用），**And** 导航不复制控件，**And** 卡片始终保持可读尺寸（FR-020/FR-021 规则）。
2. **Given** 笔记窗口，**When** 用户将其缩放到紧凑尺寸，**Then** 保持可用，**And** 不因空间充足而暴露不必要的工具栏。
3. **Given** 应用，**When** 用户只用键盘操作，**Then** 所有重要工具栏命令均可从菜单栏执行（File/Edit/View/Window/Help 惯例），**And** 全局快捷键与常用本地快捷键（⌘N、⌘F、⌘W、⌘, 等）可用，**And** 卡片网格支持方向键选择 + Return 打开 + ⌘⌫ 移入 Trash。
4. **Given** Reduce Transparency 开启，**When** 用户使用自定义控件，**Then** 控件仍可理解（不依赖半透明）；**Given** Reduce Motion 开启，**When** 动画类效果存在，**Then** 遵循系统减少动态效果。
5. **Given** Increase Contrast / Show Borders 开启，**When** 用户使用应用，**Then** 可读性不下降（边框强化、对比度提升按系统行为生效）。
6. **Given** VoiceOver 开启，**When** 用户走查 Library、笔记窗口、设置、同步状态，**Then** 所有自建控件提供明确的本地化标签与状态（001 FR-180b 政策延续），**And** 选择态不以颜色为唯一传达方式（001 FR-044）。
7. **Given** Liquid Glass 系统外观生效，**When** 用户观察应用，**Then** 玻璃只出现在功能/控制层（原生工具栏、菜单、搜索、侧边栏、按钮、弹出框、浮动上下文控件），**And** 笔记内容、卡片、编辑器表面、内容背景不是玻璃材质，**And** 应用未用手工模糊/透明度/渐变/边框/着色器模拟玻璃（存在系统行为时）。

---

### User Story 7 - 迁移与兼容（P3）

升级后的应用保持既有笔记、颜色、同步配置、加密数据、快捷键、字体、权限与偏好全部有效；加密语义与仓库格式不变。

**Why this priority**: 目标 8 与成功标准 20 是不可谈判的底线（度量见 SC-020/SC-025）；重设计不得让任何用户丢失内容或配置。

**Independent Test**: 用包含既有笔记/颜色/同步配置/偏好的迁移夹具（001 既定 fixtures）启动新版应用，验证全部数据与配置原样可用、功能行为不变。

**Acceptance Scenarios**:

1. **Given** 升级前的数据库与偏好，**When** 新版应用首次启动，**Then** 既有笔记（含 Trash 中的笔记）与块内容原样可见与可编辑，**And** 颜色、透明度、字号、置顶、窗口位置等外观状态保留。
2. **Given** 已配置的同步仓库，**When** 升级后首次同步，**Then** 配置、加密数据与解锁状态语义不变（001 FR-150/FR-154/FR-162a），**And** 不需要重新输入仓库配置。
3. **Given** 已设置的全局快捷键与字体偏好，**When** 升级，**Then** 快捷键与字体偏好保持有效。
4. **Given** 屏幕录制/辅助功能权限状态，**When** 升级，**Then** 权限状态保持（不重新请求、不丢失已知状态）。
5. **Given** 本重设计，**When** 检查加密语义与仓库格式，**Then** 两者均未改变（Constitution VII/VIII 不变）。

---

### Edge Cases

- Library 窗口宽度极窄（如 320 pt）：列数降为 1，工具栏次要控件进系统溢出，搜索仍可访问，卡片保持可读（FR-021/FR-070）。
- 同步错误持续存在（如仓库离线数日）：上下文状态条保持可见但可关闭；关闭后不再骚扰，直到状态变化或用户手动同步（FR-010）。
- 用户关闭同步状态条后又发生新的错误类别：状态条重新出现（新事件触发新呈现）（FR-010）。
- 旧版自定义颜色在深色模式下对比度不足：沿用 001 FR-042 自动前景色调整，而非拒绝颜色（FR-033）。
- 无标题笔记的卡片预览与摘要重复：沿用 001 FR-020a/FR-021（预览取首个富文本内容而非摘要；两张卡片摘要可相同，靠时间/颜色/预览区分）。
- 失活状态下用户悬停笔记窗口：浮动控件不显示或显示失活外观（FR-044/FR-045）。
- ~~快捷键录制冲突（系统/其他应用已占用）：清晰报错并保持未录制状态（001 FR-121）。~~ **REMOVED 2026-08-10**（全局快捷键移除，无录制冲突场景）。
- 用户删除"设置同步"中的 vault 解锁记忆：立即清除 Keychain 记忆但当前会话保持解锁（001 FR-162a 复用）。
- 缩放时卡片列数变化：不允许出现布局跳动或悬停操作导致卡片高度突变（FR-023）。
- 深度模式下新调色板与既有"自定义颜色 + 透明度 + Increase Contrast"组合：对比度阈值强制执行（001 FR-042/FR-182）。
- 笔记窗口在紧凑尺寸下仍有 100+ 待办：编辑器虚拟化（001 FR-072b）不因重设计回退。
- 屏幕录制权限被拒后用户仍可用普通笔记：001 FR-132 语义保留，权限面板如实展示状态与用途。
- 搜索激活期间切换目的地（Trash⇄Notes）：当前查询与排序保留，网格按新范围重新查询（FTS5 行为不变，001 FR-024 时效保持）。
- Trash 范围内搜索：与 Notes 范围一致的原生搜索行为；无匹配呈现 EmptyStateView 的 no-match 状态（CHK029）。
- 搜索期间更改排序：排序作用于当前查询结果集，模式与 001 FR-022 一致；目的地切换不复制导航控件（FR-070）。
- 菜单栏图标双交互模型：左键即时开窗（FR-001）与右键/⌥-点击下拉菜单（打开 Library/设置/帮助/关于/退出）并行；Dock 隐藏时 Quit 仅经该下拉菜单与 ⌘Q 可达（FR-006/Constitution X）。

## Scope *(mandatory)*

### In-Scope

- Library 窗口重设计：单一原生工具栏（新建、搜索、排序、导航目的地）、内容优先卡片网格、移除常驻底部工具条、Quit 移出应用 UI。
- 同步状态呈现重设计：正常态零占位，注意态上下文呈现，错误人性化，诊断隔离到高级体验。
- 笔记卡片与自适应网格重设计（密度、自适应列、选择/悬停/上下文操作）。
- 正式化克制的笔记配色系统（浅/深模式分别设计、对比度保证、旧颜色迁移映射）。
- 独立笔记窗口重设计：标准红绿灯、内容即笔记、即写即得、块插入上下文化、浮动控件玻璃呈现与失活外观。
- 设置窗口重设计：原生 Settings 导航与表单、通用（Dock 图标；Notes 分区含字体多语言预览）、同步（状态 + 高级区）、隐私（屏幕录制状态展示；2026-08-14 Rev 2：字体并入通用、权限更名隐私、移除无消费方的辅助功能行）。
- 跨窗口视觉系统（间距、排版、圆角、选择、焦点、边框、分隔、悬停/按下/禁用、激活/失活、语义状态）。
- 窗口缩放、键盘/菜单惯例、系统行为（Reduce Transparency/Motion、Increase Contrast、VoiceOver、显示比例）。
- Liquid Glass 应用于功能/控制层及平台 API 验证约束。
- 旧数据/配置迁移兼容性验证。
- ~~全局快捷键"搜索全部笔记"行为补全：`searchAll` 与 `stickynotes://search` 深链打开 Library 并聚焦搜索框（001 FR-120 动作身份不变，D8）。~~ **更新 2026-08-10**：全局快捷键已移除；`stickynotes://search` 深链行为保留（打开 Library 并聚焦搜索框，001 FR-120 动作身份由深链契约承担）。

### Out-of-Scope

- 修改任何笔记内容行为、块类型、Markdown 转换、待办身份、文件引用语义、截图/剪贴板图片行为（001 FR-050–FR-105 不变）。
- 修改加密语义、同步协议、仓库格式、冲突处理、墓碑语义（Constitution VII/VIII 不变；001 FR-160–FR-174 不变）。
- ~~修改全局快捷键的绑定集合或动作语义（例外：仅"搜索全部笔记"的打开+聚焦搜索框补全，见 In-Scope 与 FR-072）。~~ **REMOVED 2026-08-10**（全局快捷键随 001 FR-120/FR-121 移除，本约束不再适用）。
- 修改同步频率选项集合与默认值（001 FR-152 不变）。
- 修改权限请求时机与降级语义（001 FR-131–FR-134 不变；Constitution VI 不变）。
- 引入任何分析、遥测、开发者运营服务（001 FR-190/FR-191 不变）。
- 新增笔记功能（无新块类型、无协作、无 OCR、无附件同步）。
- 修改 001 的菜单栏附属窗口定位/开合行为（FR-001/FR-001a 保留）。
- 使用自定义着色器或手工视觉特效替代系统 Liquid Glass 行为。
- 最低支持系统版本变更（保持 macOS 26+；目标系统行为按 macOS 27 校验）。
- ~~WidgetExtension 表面重设计~~（WidgetExtension 已随 001 widget 删除于 2026-08-13 移除，本特性不再涉及）。

## Requirements *(mandatory)*

### Functional Requirements

**Library 窗口与工具栏**

- **FR-001**: Library 窗口 MUST 保留 001 FR-001/FR-001a 的菜单栏附属行为：位于菜单栏图标正下方 4 pt、左缘对齐图标、完整可见屏内、打开/关闭无动画即时完成；本特性在其上重设计，MUST NOT 改变定位与开合语义。菜单栏图标左键点击 MUST 打开 Library 窗口（开合语义不变）；右键（或 ⌥-点击）MUST 弹出下拉菜单：打开 Library / 设置 / 帮助 / 关于 / 退出（FR-006）。
- **FR-002**: Library 窗口 MUST 以单一原生 macOS 窗口工具栏为唯一顶层控制行；001 现有堆叠式顶部控件（大尺寸"新建笔记"块、Notes/Trash 分段控件、独立搜索行、排序控件）MUST 全部从该堆叠布局中移除，并按 FR-002a–FR-005 重新分布。
- **FR-002a**: "新建笔记" MUST 呈现为原生工具栏动作（标准工具栏项，SF Symbol 图标），视觉上紧凑、属工具栏惯例；MUST 保持最快、最可发现的操作之一（工具栏位置 + ⌘N + 全局快捷键 + 文件菜单命令），MUST NOT 再呈现为大矩形 UI 块。
- **FR-003**: 搜索 MUST 使用原生 macOS 搜索体验（工具栏搜索栏：系统外观、清空/退出行为、键盘可达），MUST 视觉上属于工具栏（单一控制行，MUST NOT 形成第二工具行）；结果更新时效 MUST 保持 001 FR-024/FR-024a（查询变化 ≤100 ms 开始更新；10,000 条笔记 ≤200 ms 完成）。实现说明（2026-08-14 修订）：MenuBarExtra(.window) 无原生 NSToolbar（T018 结论），搜索控件实现为原生 `NSSearchField`（NSViewRepresentable 桥接，保留 searchQuery 状态与 ⌘F 聚焦契约），控件本身是 AppKit 原生搜索控件而非手绘 TextField。
- **FR-003a**: 搜索框的 ⌘F 菜单命令与 `stickynotes://search` 深链 MUST 将焦点置于搜索控件（001 FR-120 动作身份不变），焦点请求经模型层 `searchFocusRequested` 消费。
- **FR-004**: 排序/过滤 MUST 呈现为次要工具栏控件（如工具栏弹出按钮或可移入溢出的控件），支持的排序模式 MUST 与 001 FR-022 一致（最近修改、最近创建、标题、手动）；其视觉权重 MUST 不高于"新建笔记"与"搜索"；排序控件 MUST 与"新建笔记""搜索"使用相同的工具栏项度量（同高度、同 inset、同视觉权重，CHK012）。
- **FR-005**: "笔记"与"Trash"两个导航目的地 MUST 以紧凑的原生模式呈现，二选一：(a) 工具栏中的紧凑目的地控件（推荐——两个目的地时优先更简单的原生方案），或 (b) 遵循当前 macOS 侧边栏行为、可折叠、宽度克制的侧边栏；Trash MUST NOT 再占据 50% 宽度的顶层分段控件；无论哪种方案，MUST 支持键盘导航与 VoiceOver。
- **FR-006**: 常驻底部工具条（Sync Issue、Retry、refresh、help、info、settings、Quit）MUST 被移除；"Quit" MUST NOT 出现在任何应用窗口 UI 中（仅应用菜单与系统机制）；Help、About、Settings、刷新、诊断等低频动作 MUST 通过常规 macOS 位置可达：菜单栏/应用菜单、工具栏溢出、设置、或上下文相关菜单；Dock 图标隐藏（LSUIElement）时，Settings/About/Help/Quit MUST 仍从菜单栏界面可达（Constitution X）——载体的交互模型见 FR-001：左键开窗、右键/⌥-点击弹出下拉菜单（打开 Library/设置/帮助/关于/退出）。
- **FR-007**: 同步成功 MUST 不消耗任何持久屏幕空间（正常态无同步页脚/指示器；FR-010 例外）。

**同步状态呈现**

- **FR-010**: 当同步需要用户注意时，MUST 以简洁的上下文状态呈现（就近横幅或内联），说明三要素：发生了什么、笔记在本地仍然安全可用、用户可采取的动作；状态可关闭，关闭后 MUST NOT 在状态无变化时重现；新错误类别出现时 MUST 重新呈现。
- **FR-010a**: 需要重试/恢复时，状态呈现中 MUST 提供明确的重试或恢复动作；该动作 MUST 触发与 001 FR-151 手动同步一致的行为，且 MUST NOT 阻塞本地编辑（001 FR-153）；恢复动作成功后（重试成功、解锁成功、重新验证成功）状态 MUST 清除回零占位，新错误类别再触发重现（CHK030）。
- **FR-011**: 内部错误标识符（如 `sync.historyAgedOut`）MUST NOT 出现在普通用户界面中；开发者导向的标识符与诊断细节 MUST 仅存在于高级诊断或导出诊断包体验中（001 FR-191 边界不变）。
- **FR-012**: 每个内部同步错误类别 MUST 有确定性的 错误→可读描述→恢复动作 映射（zh-Hans/en 本地化，001 FR-180a），映射 MUST 可被自动化测试穷举验证（描述不含内部标识符、不含敏感信息）。普通界面 MUST 按用户所需动作分组呈现为七类可读状态，而非平铺引擎内部全部分类：①无法连接仓库（离线/仓库不可达，提供重试）②认证失败（需重新验证凭据）③需要解锁（需输入同步密码）④有未同步更改（信息性，可手动同步）⑤已创建冲突副本（提示并可查看，"查看"动作 MUST 打开对应冲突副本笔记的既有笔记窗口，001 ConflictCopyView/NoteWindowCoordinator 语义，本特性不新建视图）⑥同步历史已过期（仅告知，本地内容安全、无需强制动作，001 FR-174 语义）⑦仓库损坏/不兼容（需高级处理：替换或重新加入）。多类别同时活跃时，MUST 按确定性优先级呈现最高者：⑦ 仓库损坏/不兼容 > ③ 需要解锁 > ② 认证失败 > ① 无法连接 > ⑤ 冲突副本 > ④ 有未同步更改 > ⑥ 历史过期（纯函数，穷举测试断言）。

**笔记网格与卡片**

- **FR-020**: 卡片 MUST 明显比 001 FR-002a 的 220×160 pt 更紧凑（密度目标见 SC-022），卡片信息按递减视觉优先级呈现：(1) 笔记标题或首个有意义行（001 FR-021 摘要规则沿用），(2) 内容预览（如有），(3) 修改时间；卡片内部 MUST NOT 存在大面积未利用空白。
- **FR-021**: 卡片网格 MUST 自适应窗口宽度，遵循确定性规则：最小卡片宽度 180 pt、间距固定 12 pt，列数 = `max(1, floor((内容宽度 + 12) / 192))`，卡片宽度 = `(内容宽度 − (列数−1) × 12) / 列数`（随宽度连续变化；3–4 列典型宽度下卡片宽 180–228 pt，2 列可达约 276 pt、1 列取全宽，无固定上限）；窗口变窄时列数渐进减少、变宽时增加；MUST 以"最近修改"为默认排序并按 001 FR-022 全部模式可排序。
- **FR-022**: 卡片 MUST 属于内容层，MUST NOT 使用 Liquid Glass；与 Library 背景的区分 MUST 通过克制的原生手段（细边框、微妙深度、间距、选择态、悬停反馈），MUST NOT 使用夸张阴影、渐变、人工光泽或模拟纸张纹理。
- **FR-023**: 卡片选择态 MUST 明显但不喧宾夺主，且 MUST 不依赖颜色作为唯一传达（001 FR-044）；悬停可揭示上下文操作，但这些操作 MUST NOT 引起卡片布局跳动（出现/消失不改变尺寸）。
- **FR-024**: 卡片 MUST 支持 Mac 惯例交互：单击选择、双击打开、上下文菜单、键盘导航（方向键移动选择、Return/Enter 打开、⌘⌫ 移入 Trash）、删除/移入 Trash、以及在手动排序下延续 001 FR-022a 的拖拽排序。
- **FR-025**: 卡片信息字段 MUST 沿用 001 FR-020/FR-020a/FR-021 的语义与确定性规则（2 行预览截断、相对/绝对时间边界、待办进度、封面缩略图、冲突/同步警示标识），并按 FR-020 的优先级适配更紧凑的布局。
- **FR-026**: 删除确认语义：移入 Trash MUST 不要求确认（30 天可恢复期即撤销机制，001 FR-014）；永久删除——单条"永久删除"与"清空 Trash"（001 FR-014b）——MUST 均要求显式确认，确认文案说明该操作立即且永久删除、30 天可恢复保证不再适用（001 FR-014b 语义延伸至单条永久删除）。

**笔记配色系统**

- **FR-030**: MUST 引入正式化、克制的内置调色板，至少包含：黄、桃、粉、绿/薄荷、蓝、薰衣草、中性灰七种；调色板 MUST 服务于"颜色标识笔记、提供个性，不降低文本对比度"。
- **FR-031**: 每个内置颜色 MUST 在浅色与深色外观下各有一套刻意设计的颜色值（两套取值均来自设计，MUST NOT 是对同一 RGB 做机械透明度/亮度变换）；两套取值 MUST 均满足 001 FR-042 阈值：主文本 ≥4.5:1、大文本与活动控件 ≥3:1，且次文本、选择态与控件同样达标（对比度校验以真实渲染背景为输入，001 FR-042 语义延续）。
- **FR-032**: 自定义颜色能力 MUST 保留（001 FR-040）；迁移后，旧内置颜色（001 FR-040a 六色）MUST 按语义映射到新调色板对应颜色（黄→黄、粉→粉、紫→薰衣草、蓝→蓝、绿→绿、灰→灰），自定义颜色 MUST 原值保留并继续可用；任何颜色迁移 MUST 不改变笔记内容。
- **FR-033**: 前景自动调整 MUST 延续 001 FR-042：任何"自定义颜色 + 透明度 + 外观/Increase Contrast"组合若低于阈值，应用 MUST 自动调整前景色至达标，而非拒绝颜色。

**独立笔记窗口**

- **FR-040**: 笔记窗口 MUST 保留标准 macOS 窗口行为与标准红绿灯控件；窗口的移动、缩放、最小化、关闭语义 MUST NOT 回归（001 FR-006/FR-007/FR-032 不变）。
- **FR-041**: 内容区 MUST 呈现为笔记本身：笔记色、以配置透明度渲染（001 FR-041/FR-041a 不变）、默认不透明、非玻璃材质；MUST NOT 呈现为嵌入大型应用外观中的编辑器。
- **FR-042**: 新建笔记窗口打开时（Library/全局快捷键/菜单/深链/小组件，001 FR-007a 全路径），MUST 立即将键盘焦点置于内容顶部附近，内容首行与窗口内容区顶端 MUST NOT 存在大段无解释的空白；用户 MUST 无需选择块类型即可立即输入普通富文本（量化判定：首行基线与内容区顶端间距 ≤ 编辑器顶部内边距 + 1 个行高；T028 断言该阈值）。
- **FR-043**: 常驻可见的 "Add Block" 首屏控件 MUST 被移除；块插入 MUST 转为上下文能力，采用"插入点附近的微妙添加控件 + 原生菜单/键盘命令"组合（不引入 "/" 命令系统）；块功能（001 FR-050/FR-050a/FR-050b 全部块类型与行为）MUST 完整保留。
- **FR-044**: 浮于笔记上方的控件（颜色、添加、格式等）MAY 在适当时使用当前原生 Liquid Glass 呈现（仅限自定义交互控件）；MUST 仅在有用时出现、不常驻遮挡笔记内容、随指针离开/失焦合理隐藏；MUST 按 macOS 惯例呈现失活状态外观。
- **FR-045**: 笔记窗口 MUST 在激活与失活状态下均可用；失活状态下强调色/强调元素 MUST 呈现 macOS 预期的失活外观（不保留不恰当的强调强调）。

**设置窗口**

- **FR-050**: 设置窗口 MUST 采用原生 macOS Settings 工具栏式标签导航（System Settings 风格），替代大尺寸自定义分段导航；逻辑区域 MUST 为：通用、同步、隐私（2026-08-14 Rev 2 修订：字体并入通用面板 Notes 分区，权限面板更名为隐私面板）。
- **FR-051**: 设置各面板 MUST 遵循原生表单惯例（对齐、间距、控件、分隔线、标签、说明文字、分组）；MUST NOT 将每个分区放入大圆角灰矩形容器。设置窗口 MUST 具有稳定的 window shell（2026-08-14 Rev 2 修订）：切换设置分区 MUST NOT 改变窗口 geometry；窗口 MUST NOT 可缩窄至一级导航发生 overflow/折叠；默认尺寸 MUST 完整显示通用与隐私面板；同步面板内容溢出时 MUST 在内容区内滚动；en 与 zh-Hans 文案 MUST NOT 破坏布局。具体尺寸值由实现层 SettingsWindowPolicy 定义，规格不写死数值。
- **FR-052**（通用）: 面板 MUST 保留"显示 Dock 图标"开关（全局快捷键项已于 2026-08-10 随 001 FR-120/FR-121 移除，不再呈现）。
- **FR-053**（同步）: 默认同步页面 MUST 聚焦用户概念：同步状态、存储位置、上次成功同步时间、自动同步开关、定期同步 Periodic sync（001 FR-152 选项与默认值不变；2026-08-14 Rev 3 更名，UI 标签为 "Periodic sync"、"Off"）、本 Mac 上 vault 解锁状态（001 FR-162a 不变）、主同步/重试动作；错误 MUST 按 FR-012 呈现为可读描述与恢复动作；同步状态 MUST 由 FR-012 分类映射驱动（2026-08-14 Rev 2 修订），MUST NOT 以内部 "Configured" 状态冒充用户状态；vault 未解锁时 MUST 如实显示锁定状态并禁用不可执行控件（解锁入口 MAY 提供）。2026-08-14 Rev 3 修订：周期同步 schedule 是设备本地偏好（001 FR-152），vault 锁定态下 MUST 仍可配置（仅自动同步总开关关闭时禁用）；锁定 caption MUST 说明解锁后可手动或自动同步，并保留"本地笔记仍可用"条款。
- **FR-054**（同步·高级）: "加入既有保险库" MUST 作为首次配置流程的一部分（初始设置），并在 Storage 区 "Manage…" 菜单提供重入入口（2026-08-14 Rev 3 修订：重入入口由 Advanced 移至 Storage "Manage…"；Join Another Vault 为独立产品动作，MUST NOT 并入"更改存储位置"流程）；"新建存储位置" MUST 与 Join 并列于 "Manage…" 菜单（独立动作不合并流程）；"导出同步配置""导出诊断包"等导出类维护操作 MUST 位于独立"高级"管理区，与常规偏好分离；"断开同步"（原"移除配置"）MUST 独立于 Advanced，呈现为表单底部单独的破坏性入口（确认与视觉/语义区分要求不变）；新建存储位置 MUST 保持 001 FR-154 语义（本地笔记保留、新 vault 全新引导、不自动删除旧仓库远程数据）且确认文案 MUST 明示该语义；破坏性操作 MUST 在视觉与语义上与常规操作区分，并 MUST 要求相应确认；加密密码丢失警告（001 FR-163）MUST 采用标准警告样式与简洁文案（稳定配置态下收敛为 Recovery 信息行，位于 Security 分区），MUST NOT 主导整个面板。
- **FR-055**（通用·Notes）: 通用面板 MUST 面向普通用户提供"正文字体"概念（主字体 + 系统回退，不使用实现性排版术语；2026-08-14 Rev 3 修订：名称明确为 Note body font，只承诺正文渲染）；中英文 MUST 自然混排（001 FR-043 行为不变）；默认值 MUST 对齐 macOS 系统排版与系统回退；MUST 提供有意义的多语言实时预览（2026-08-14 Rev 3 修订：预览为多行样本并真实应用 Text Spacing 的 lineSpacing，字体与间距变更即时可见）；卡片正文预览 MUST 跟随用户正文字体（字号仍用卡片预览字号、2 行截断不变），卡片标题保持系统 headline（信息层级，不跟随）。
- **FR-055a**: "正文字体"选择 MUST 使用系统字体族列表（`NSFontManager.availableFontFamilies`），以菜单选择呈现（"System Default" 对应未设置态 nil=系统字体）；选择即提交（无文本输入的逐键提交/失焦提交路径）。
- **FR-056**（隐私，2026-08-14 Rev 2 修订）: 隐私面板 MUST 只展示当前有实际功能消费方的权限：屏幕录制权限 MUST 展示当前状态、为何需要、依赖的功能、打开/发起系统权限流程的动作；权限状态 UI MUST NOT 暴露公开 API 无法可靠观测的状态区分（未授予不得细分 not-determined/denied）；无消费方功能的权限（当前：辅助功能——保留给未来高级窗口识别，001 FR-130）MUST NOT 出现在设置中诱导预授权；请求时机 MUST 保持懒请求（001 FR-131/FR-132/FR-133 与 Constitution VI 修订后语义不变）。

**Liquid Glass 与系统行为**

- **FR-060**: Liquid Glass MUST 仅用于功能/控制层（原生工具栏、菜单、搜索、侧边栏、表单、按钮、弹出框、导航、上下文浮动控件）；笔记内容、卡片、编辑器表面、普通内容背景 MUST NOT 变为玻璃表面。
- **FR-061**: MUST 优先使用系统提供的控件/行为（自动获得正确的系统外观、指针行为、激活/失活状态、无障碍响应、深色模式与未来 Liquid Glass 细化）；自定义玻璃 MUST 仅用于真正需要自定义的交互控件；MUST NOT 出现玻璃叠玻璃；可读性重要处 MUST 优先常规玻璃外观；clear 玻璃 MUST NOT 作为本效率应用默认（仅可考虑用于以"看到内容"为首要目标的视觉丰富内容上）；交互式玻璃 MUST 仅用于交互控件；关系紧密的自定义玻璃控件 MUST 视觉上表现为连贯的组而非无关浮动胶囊。
- **FR-062**: MUST NOT 在存在合适系统行为时用手工模糊、透明度、渐变、边框或自定义着色器复刻 Liquid Glass；自定义控件 MUST 在 Reduce Transparency / Reduce Motion / Increase Contrast / Show Borders 下仍然可理解；排版、颜色、图标、命中目标 MUST 不依赖半透明仍可辨认。
- **FR-063**: 应用行为 MUST 在以下条件下全部正确：当前 macOS 27 Liquid Glass 外观、用户选择的 Liquid Glass 系统外观、浅色/深色模式、系统强调色、激活/失活窗口、Increase Contrast/Show Borders、Reduce Transparency、Reduce Motion、纯键盘导航、VoiceOver、不同显示比例、窄与宽可缩放窗口。
- **FR-064**: 通用动作 MUST 使用 SF Symbols 与标准 macOS 图标，MUST NOT 使用自定义位图图标。

**窗口缩放与 Mac 惯例**

- **FR-070**: Library MUST 在实用宽度范围内保持可用：宽窗口显示更多列、窄窗口渐进减少列（FR-021 规则）；次要工具栏控件 MUST 移入系统溢出而非压缩内容至不可用；导航 MUST 随宽度适配且不复制控件；卡片 MUST 保持可读尺寸（180 pt 最小宽度）。
- **FR-071**: 笔记窗口 MUST 在紧凑尺寸下保持可用，MUST NOT 仅因空间充足而暴露不必要工具栏。
- **FR-072**: 每个重要工具栏命令 MUST 有对应的菜单栏命令（按 macOS 惯例位于 File/Edit/View/Window/Help）；常用本地快捷键（⌘N 新建、⌘F 搜索、⌘W 关闭、⌘, 设置、⌘⌫ 移入 Trash 等）MUST 遵循 macOS 标准；MUST NOT 在已有 macOS 标准等价物时发明自定义交互；上下文菜单 MUST 暴露有用的笔记操作（如颜色、置顶、导出、移入 Trash、002/001 既定操作），MUST NOT 复制整个应用菜单。"搜索全部笔记"深链 `stickynotes://search` MUST 打开 Library 并聚焦搜索框（001 FR-120 动作身份由深链契约承担；全局快捷键部分已于 2026-08-10 移除）。2026-08-14 修订：Restore、Empty Trash…、Sync Now 三个动作 MUST 有菜单栏命令（File 区，无自定义快捷键）；Empty Trash… 菜单命令与 Library ⋯ 菜单共用同一模型层确认机制（FR-026 确认语义不变）。

**视觉系统**

- **FR-080**: MUST 建立跨 Library/笔记窗口/设置的连贯视觉系统，覆盖：间距、排版、笔记颜色、圆角、选择、焦点、边框、分隔线、悬停、按下、禁用、激活/失活窗口、语义警告/错误/成功状态；MUST 优先使用 macOS 系统度量而非任意放大的内边距与圆角。
- **FR-081**: 分组 MUST 首先通过对齐、间距、层级、分隔线与标准表单/列表行为表达，然后才考虑圆角背景面板；MUST 减少可见容器数量。
- **FR-082**: Library、设置、笔记窗口 MUST 属于同一产品并清晰表达同一视觉语言，同时各自服务于不同目的。

**注**: 本规范中"明显/微妙/克制"等设计判断词以 `checklists/design.md` 对应 CHK 断言为实现验收标准。

**迁移与兼容**

- **FR-090**: 本重设计 MUST 保留既有笔记、Trash 中笔记、已存颜色、同步配置、加密数据、快捷键、字体、权限与偏好全部有效；MUST NOT 因 UI 现代化丢失任何笔记内容或配置；MUST NOT 改变加密语义或仓库格式（Constitution VII/VIII；001 FR-160–FR-174 不变）。
- **FR-091**: 001 的性能目标 MUST 在重设计后保持：菜单栏 Library 暖启动 ≤150 ms（001 SC-001）、卡片内容 ≤300 ms 可见（SC-002）、新笔记窗口 ≤200 ms 呈现（SC-003）、击键到字形 <16 ms（SC-004a）、10,000 条笔记搜索 ≤200 ms（SC-005）、空闲无持续 CPU 使用与高频轮询（SC-006）。

### Key Entities *(include if feature involves data)*

- **NoteColor（内置调色板条目）**: 内置颜色定义（黄/桃/粉/绿/蓝/薰衣草/灰），每条目含浅色与深色两套设计值及对比度验证结果；区别于用户自定义颜色（原样存储值）。
- **SyncStatusPresentation（同步状态呈现模型）**: 内部错误类别 → 可读描述（zh-Hans/en）→ 恢复动作 → 是否需要用户注意 的确定性映射；仅影响呈现，不改变同步引擎。
- **Note Card（重设计后的卡片）**: 呈现层实体，聚合标题/摘要、预览、修改时间、颜色、待办进度、封面、警示标识；遵循 FR-020/FR-021/FR-025 呈现规则。
- **Shortcut Binding（快捷键条目）**: 全局动作 → 快捷键 的映射（含当前值、录制状态、冲突状态），与 001 既有动作一一对应，仅呈现/录入界面重设计。

## Data & Migration Implications

- 颜色：既有内置六色按 FR-032 语义映射到新调色板；自定义颜色值原样保留。颜色以既有存储值迁移，预期无数据库 schema 变更；任何呈现层新颜色定义（浅/深两套）仅作为应用内常量，不入库。
- 偏好：快捷键、字体、同步频率、vault 记忆解锁等偏好键语义不变；若呈现层需要偏好键更名，MUST 提供确定性的一次性迁移（读写旧键，失败时回退旧键），且 MUST 有迁移测试。
- 同步：错误呈现模型（FR-012 映射）为纯呈现层新增；不同步任何新字段、不改变 001 契约（`contracts/` 下 schema 全部不变）。
- 数据完整性：本特性不新增/删除任何本地数据库字段；001 迁移 fixtures（`Fixtures/schema_vN.sqlite`）继续有效；升级路径 MUST 有"旧数据 + 新 UI"夹具测试（FR-090）。
- 无用户内容转换：不重写任何笔记内容、块、待办、资产、墓碑或同步元数据。

## Privacy & Permission Implications

- 无新系统权限：本特性不请求屏幕录制/辅助功能之外的新权限；权限请求时机与降级语义不变（001 FR-131–FR-134；Constitution VI）。
- 权限面板呈现：展示状态/用途/动作，不诱导授权；未使用功能对应的权限如实标注"未使用/可选"（Constitution VI 2.0.0 修订语义）。
- 同步错误文案（FR-012）MUST 不含内部标识符、端点 URL、凭据或任何敏感细节；诊断边界维持 001 FR-191 正向枚举（导出诊断包字段清单不变）。
- 日志与诊断不得包含笔记内容、文件名/路径、窗口标题（Constitution VI）；本特性新增的呈现层日志（如有）同样受限。

## Accessibility Implications

- 所有新增/重设计控件 MUST 支持键盘操作与 VoiceOver，遵循 001 FR-180b 政策：标准控件用平台默认标签；自建控件（卡片选择态、浮动玻璃控件、快捷键录制器、同步状态条）提供明确本地化标签与状态。
- 选择态、完成态、警告/错误态 MUST 不以颜色为唯一传达（001 FR-044/FR-182）。
- 配色系统 MUST 在浅/深/自定义颜色/透明度/Increase Contrast 全组合下满足 001 FR-042 阈值（FR-031/FR-033）。
- Reduce Transparency / Reduce Motion / Increase Contrast / Show Borders 下的可理解性 MUST 通过自动化断言与人工走查验证（FR-062/FR-063）。
- 快捷键录制界面 MUST 完全键盘可操作（录制/重置/取消全程无需指针）。
- VoiceOver 必须能读出同步状态条的三要素与恢复动作（FR-010）。

## Performance Expectations

- 保持 001 SC-001/SC-002/SC-003/SC-004a/SC-005/SC-006 全部目标（FR-091）；重设计不得以视觉层代价牺牲它们。
- 卡片网格在 10,000 条笔记规模下 MUST 使用懒加载/虚拟化（001 FR-094a 缩略图与 001 FR-072b 待办虚拟化不回退）；滚动流畅。
- 搜索行为与 001 FR-024/FR-024a 一致（底层 FTS5 不变，仅表面重设计）。
- 玻璃效果由系统渲染：本特性 MUST NOT 引入手工模糊/图层开销；自定义浮动控件使用系统玻璃 API（见平台约束节），其出现/隐藏动画遵循系统行为，空闲时零开销（SC-006）。

## Failure & Recovery Behavior

- 同步错误：按 FR-010/FR-012 呈现人话状态 + 恢复动作；重试不阻塞本地编辑（001 FR-153）；状态条关闭不丢失诊断（诊断仅在高级体验）。
- Library 动作失败（打开笔记、切换排序、搜索）：沿用 001 FR-011a 韧性保证（不崩溃、不丢数据、非阻塞本地化提示）。
- ~~快捷键录制冲突：清晰报错并保持未录制状态（001 FR-121）。~~ **REMOVED 2026-08-10**（全局快捷键移除）。
- 设置面板加载/保存失败：非阻塞提示，不改写用户数据（001 FR-011a 语义延伸）。
- 窗口状态异常（失活外观、缩放极端值）：回退到系统默认行为，不崩溃、不丢笔记。
- 迁移失败：任何偏好/颜色迁移 MUST 原子回退（旧值保留），应用照常启动（FR-090/Data & Migration）。

## Platform Design Constraint / API Validation Requirement

本规范描述产品行为而非实现架构，但所有后续实现规划 MUST 以当前 macOS 27 SDK 为目标，并在使用前对照当前 Apple 开发者文档验证平台 API。

对于 Liquid Glass 及相关平台行为，实现计划可以依赖当前真实存在的公共 Apple API，包括：

SwiftUI：
- `glassEffect(_:in:)`、`Glass`、`Glass.regular`、`Glass.clear`、`Glass.identity`、`Glass.tint(_:)`、`Glass.interactive(_:)`、`GlassEffectContainer`、`glassEffectID(_:in:)`、`glassEffectTransition(_:)`、`glassEffectUnion(id:namespace:)`、`toolbar(content:)`、`sharedBackgroundVisibility(_:)`、`visibilityPriority(_:)`、`EnvironmentValues.appearsActive`、`EnvironmentValues.accessibilityShowBorders`、`EnvironmentValues.accessibilityReduceTransparency`、`EnvironmentValues.accessibilityReduceMotion`

AppKit（仅当确需 AppKit 层集成时）：
- `NSGlassEffectView`、`NSGlassEffectContainerView`、`NSGlassEffectView.effectIsInteractive`、`NSGlassEffectView.tintColor`、`NSGlassEffectView.cornerRadius`、`NSButton.BezelStyle.glass`、`NSBackgroundExtensionView`、`NSToolbar` 与标准 macOS 窗口/工具栏行为

MUST NOT 发明 API 名称、修饰符、材质、环境键或 Liquid Glass 兼容性标志。若上述任一 API 在项目实际安装的 SDK 中已变更、仅限 beta 或可用性不同，实现阶段 MUST 对照已安装的 macOS 27 SDK 与当前 Apple 文档验证，并使用文档记载的等价物；MUST NOT 静默以自定义视觉仿制代替。

## Required Tests *(Constitution XII/XIV)*

- UI 测试（AppUITests）：Library 工具栏结构（单一工具栏、无底部栏、无 Quit 入口）；新建笔记即获得焦点并可直接打字；搜索属于工具栏；排序为次要控件；Notes/Trash 导航呈现；卡片单击选择/双击打开/上下文菜单/键盘导航/⌘⌫；悬停操作不引起布局跳动；笔记窗口红绿灯与失活外观；设置四面板结构与导航。
- 单元测试：FR-012 错误映射（每个内部错误类别 → 可读描述/恢复动作，无内部标识符泄漏，zh-Hans/en 齐全）；FR-021 列数规则（各宽度确定性列数与卡片尺寸范围）；FR-031 调色板对比度（浅/深 × 七色 × 主/次/控件，WCAG 2.2 断言）；FR-032 颜色迁移映射（旧六色 → 新调色板、自定义颜色原值）；FR-042 焦点/空白断言（新窗口光标位置）；FR-052 快捷键录制冲突语义。
- 迁移测试：旧数据库/偏好夹具 + 新 UI 启动（笔记、颜色、同步配置、快捷键、字体、权限、vault 记忆全保留）；偏好键更名迁移（如有）原子回退测试。
- 系统行为测试：Reduce Transparency / Reduce Motion / Increase Contrast / Show Borders 下自定义控件可理解性断言（如环境键驱动的外观断言）；失活窗口外观断言；显示比例断言（若可行）。
- 性能验证：001 SC-001/002/003/004a/005/006 回归（FR-091）；10,000 笔记网格虚拟化滚动与搜索时效。
- 无障碍与本地化测试：新增控件键盘/VoiceOver 可访问；zh-Hans/en 文案完整（001 FR-180a）。
- 回归：001 全部测试套件 + AppTests + UI 旅程保持绿色；~~WidgetExtension 行为不回退（001 FR-110a/FR-111/FR-112）~~（widget 已移除 2026-08-13）。
- 平台 API 验证任务：对照已安装 macOS 27 SDK 验证平台约束节所列 API 的可用性与签名，记录到 `Documentation/toolchain.md`（001 T008 延续）。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 用户打开 Library，笔记是绝对视觉主体而非控件（视觉审查 + 布局断言：工具栏高度 ≤ 原生工具栏度量，内容区 ≥ 80% 窗口高度；同步横幅出现时计入内容区，与 SC-022 同坐标系）。
- **SC-002**: 创建笔记只需一个明显动作或既有快捷键（工具栏按钮 / ⌘N / 全局快捷键任一路径均 ≤ 一步）。
- **SC-003**: 新建笔记立即进入可打字状态：窗口打开即获焦（001 FR-007a），100% 测试中无需额外点击即可开始输入。
- **SC-004**: "Add Block" 不再主导编辑器：首屏常驻块插入控件不存在；块插入经上下文途径在 100% 测试中可达。
- **SC-005**: Library 不存在常驻底部工具条（100% 测试断言）。
- **SC-006**: Trash 可用但在视觉上从属于"笔记"集合（导航呈现断言：不再有 50% 宽度分段控件）。
- **SC-007**: 搜索呈现为原生 Mac 工具栏体验的一部分（单一控制行断言）。
- **SC-008**: 卡片相对 001 显著紧凑：默认宽度下卡片高度由 160 pt 降至 ≤ 128 pt（降幅 ≥ 20%，内容填满卡片主体；上下界与空白占比由 SC-022 提供）。
- **SC-009**: 卡片为非玻璃内容表面（材质断言：卡片不应用玻璃效果）。
- **SC-010**: Liquid Glass 主要出现在原生导航/控制表面与上下文控件中（视觉审查清单逐项通过，无装饰性玻璃）。
- **SC-011**: 设置不再包含超大空白画布或不必要的灰色圆角容器（各面板内容尺寸断言）。
- **SC-012**: 同步错误以可读描述与动作呈现：100% 的错误类别测试用例中普通 UI 无内部标识符（FR-011/FR-012 穷举）。
- **SC-013**: 高级同步维护操作与常规同步偏好分离（2026-08-14 Rev 3 修订：导出类维护操作位于 "Advanced" 区、Join/新建存储位置位于 Storage "Manage…" 菜单、断开同步为独立破坏性入口，均有断言）。
- **SC-014**: 所有主要视图在浅色与深色模式下正确工作（Library/笔记/设置/Trash/搜索/同步状态逐视图检查；验收以 T074 视觉 QA 矩阵逐视图浅/深项为准）。
- **SC-015**: Reduce Transparency、Reduce Motion、Increase Contrast/Show Borders 下界面仍可理解（系统行为测试通过）。
- **SC-016**: 窗口失活状态正确、无不当强调色残留（断言 + 人工检查）。
- **SC-017**: 重要操作指针与键盘双可达：100% 的重要工具栏命令有菜单栏命令（FR-072 清单校验）。
- **SC-018**: 应用呈现为原生 macOS 27 应用（Apple HIG 走查清单：非 iPad UI、非网页仪表盘、非自定义仿制）。
- **SC-019**: 存在合适系统行为时，未用手工模糊/透明度模拟 Liquid Glass（代码审查断言）。
- **SC-020**: 重设计不丢失任何用户数据或同步配置：100% 迁移夹具测试通过（FR-090）。
- **SC-021**: 按 FR-021 公式的确定性断点：内容宽度 ≥ 756 pt 显示 ≥ 4 列（约 920 pt 的默认 Library 宽度为 4 列）；≥ 3 列要求 ≥ 564 pt；≥ 2 列要求 ≥ 372 pt；以下为 1 列。
- **SC-022**: 卡片密度：默认宽度下卡片高度 ≤ 128 pt 且 ≥ 72 pt，卡片内空白占比不超过 20%（截图上界断言，以典型内容为样本）。
- **SC-023**: 用户在重设计后完成核心捕获循环（打开 Library、创建、输入、关闭、重开、搜索找到）时间 ≤ 30 秒（001 SC-011 保持）。
- **SC-024**: 001 性能目标全部保持（FR-091 所列 SC-001/002/003/004a/005/006 回归通过）。
- **SC-025**: 既有用户数据 100% 无丢失：含旧六色笔记、自定义颜色笔记、Trash 笔记、同步配置、快捷键、字体、权限状态的夹具升级后全部有效（FR-090/FR-032）。

## Assumptions

- 本特性延续"菜单栏为主要入口"的产品模型（001 FR-001 系列）：重设计的 Library 窗口仍是菜单栏附属窗口，仅内部布局/工具栏重设计。
- 笔记窗口采用"标准红绿灯 + 与笔记表面整合的标题区域"：无独立工具栏外观（FR-040/FR-041），可编辑可选标题保留（001 FR-031 语义）。
- 内置调色板的浅/深两套取值由实现阶段按 FR-031 设计并经过 FR-042 阈值校验；本规范不预先固定十六进制值（001 FR-040a 的旧六色被本特性 FR-032 语义取代）。
- 两个导航目的地采用更简单的原生工具栏目的地方案（FR-005 (a)）为默认；侧边栏仅在实现评估认为必要且满足可折叠系统行为时使用。
- 自适应网格规则按 FR-021 的确定性公式实现；卡片高度由内容驱动、受 SC-022 界限约束。
- 块功能与全部编辑器行为（001 FR-050–FR-105）不变，仅插入呈现方式改变（FR-043）。
- 同步引擎、加密、契约 schema（`contracts/`）、冲突与墓碑语义不变（FR-090）。
- ~~全局快捷键动作集合不变（001 FR-120）；仅录入界面与呈现重设计（FR-052）；"搜索全部笔记"增加聚焦搜索框的呈现补全（FR-072）。~~ **REMOVED 2026-08-10**（全局快捷键随 001 FR-120/FR-121 移除；`stickynotes://search` 深链的聚焦补全保留）。
- ~~本特性不修改 WidgetExtension 的呈现；仅保证其行为不回退。~~（WidgetExtension 已移除 2026-08-13）。
- 平台 API 清单为规划期约束：实际可用性以安装的 macOS 27 SDK 为准（见平台约束节）。
- 本规范语言遵循 002 先例（中文 + 英文术语/FR 引用）；交付物本地化仍为 zh-Hans/en（001 FR-180a）。
