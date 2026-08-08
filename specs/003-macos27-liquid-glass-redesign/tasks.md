# Tasks: macOS 27 原生质感重设计（Liquid Glass）

**Input**: `/specs/003-macos27-liquid-glass-redesign/` design docs.
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md.
**Tests**: MANDATORY (Constitution XII). Every user story includes test tasks written FIRST and must FAIL before implementation.
**Organization**: Tasks grouped by user story (US1–US7) for independent implementation/testing. Phases follow plan.md §15 (Phase 0 基线 → 共享基础 → Library → 笔记窗口 → 配色 → 设置 → 同步 UX → 系统行为 → 迁移 → 精修)。tasks Phase N ↔ plan §15 Phase N−1（Phase 1=plan Phase 0；Phase 10 Polish 含 plan Phase 7 的 QA 部分；US3 配色使用 plan Phase 1 常量 + 笔记窗口 UI）。StickyCore 与 WidgetExtension **零改动**（REUSE）；App 层以 REFACTOR 为主，新增 `Features/DesignSystem/`。
**设计清单联动**: 本版任务已吸收 `checklists/design.md` 标志的缺口——CHK002（多类别横幅优先级）、CHK004（工具栏焦点序）、CHK006/CHK033（加入 vault 首次配置流程）、CHK029（组合态搜索）、CHK031（设置面板加载/保存失败）、CHK039（1024-gap 手动序回归）、CHK040（搜索框 IME）、CHK062（001 规格失效 FR 标记）。

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: Parallelizable (different files, no dependencies on incomplete tasks)
- **[Story]**: User story (US1–US7, priority per spec.md)
- Include exact file paths in descriptions
- Tests written FIRST, must FAIL before implementation

## Path Conventions

Native macOS app. Repository layout (plan.md §Project Structure):

```text
App/Sources/App/                        # 入口/命令体系
App/Sources/Features/{Library,NoteWindow,Editor,Settings,Trash,Shared,Capture,About}
App/Sources/Features/DesignSystem/      # 新增：语义颜色/网格度量/间距排版令牌
AppTests/   AppUITests/   Documentation/   specs/
```

所有路径仓库相对。构建/测试一律前缀 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`（quickstart.md；StickyCore: `swift test --package-path Packages/StickyCore`；App: `xcodebuild build/test -project StickyNotes.xcodeproj -scheme StickyNotes ... CODE_SIGNING_ALLOWED=NO`）。

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 基线安全（plan Phase 0）：全量回归基线、SDK/API 证据冻结、回退可测。不产生任何行为代码改动。

- [X] T001 Run full baseline regression per quickstart.md §基线验证: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore` + `xcodebuild build/test -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO`; record all-green baseline (StickyCore 92 suites, AppTests 44, AppUITests 5) with zero code changes; log any pre-existing failures before redesign work begins
- [X] T002 Validate every platform API listed in spec.md §Platform Design Constraint (SwiftUI `glassEffect(_:in:)`/`Glass`/`GlassEffectContainer`/`glassEffectID`/`glassEffectTransition`/`glassEffectUnion`/`sharedBackgroundVisibility`/`visibilityPriority`/`appearsActive`/`accessibilityShowBorders|ReduceTransparency|ReduceMotion`; AppKit `NSGlassEffectView`/`NSButton.BezelStyle.glass`/`NSBackgroundExtensionView`/`NSToolbar`) against installed SDK at `/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.0 27A5228h, macOS 27.0 SDK); confirm availability per deployment target macOS 26.0 (`visibilityPriority`=26.1, `effectIsInteractive`=27.0 → must be `#available`-guarded; `appliesShadow` overload and `ToolbarItemPlacement.search` confirmed absent); record findings in `Documentation/toolchain.md` (延续 001 T008; plan.md §4/§5)
- [X] T003 [P] Add regression snapshot tests for behaviors the redesign must preserve: current grid constants (220×160 → new formula), Library window structure (single window, click-outside close, 4pt/left-aligned positioning per 001 FR-001/001a), sync footer existence/absence, note window red-light behavior — extend `AppTests/GridMetricsTests.swift`, `AppTests/LibraryWindowPresentationTests.swift`, `AppTests/NoteWindowLifecycleTests.swift`; all MUST pass on current code (redesign-agnostic baseline)

**Checkpoint**: Baseline recorded; API evidence frozen in `Documentation/toolchain.md`; regression snapshot green.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 共享原生呈现基础（plan Phase 1）：DesignSystem（调色板/网格度量/间距令牌）、命令体系、无障碍地基。阻塞 US1–US6（US3 的调色板常量因 US1 卡片需要而前置于此，测试先行）。

**⚠️ CRITICAL**: 无用户故事可在本阶段完成前开始。

### Tests for Foundational (FIRST — must FAIL before implementation)

- [X] T004 [P] Write FR-031 contrast tests in new `AppTests/PaletteContrastTests.swift`: for each of 7 palette colors (yellow/peach/pink/green/blue/lavender/gray) × light/dark appearance × primary text ≥4.5:1, large-text/active-control ≥3:1 (001 FR-042 thresholds), plus secondary-text/selection/control states; assert against real rendered background values, not source constants — MUST FAIL (NotePalette does not exist yet)
- [X] T005 [P] Write FR-032 migration mapping tests in new `AppTests/PaletteMigrationTests.swift`: old six colors (yellow/pink/purple/blue/green/gray) map semantically to new palette (紫→薰衣草), custom colors preserved byte-exact, migration never alters note content — MUST FAIL (mapping not implemented)
- [X] T006 [P] Write SC-017 menu checklist test in new `AppTests/MenuChecklistTests.swift`: every important toolbar command (new note, search focus, sort, Notes/Trash destination, move-to-Trash, permanent delete, settings, help, about) has a menu-bar command in File/Edit/View/Window/Help — MUST FAIL (no CommandGroup yet)

### Implementation for Foundational

- [X] T007 Create `App/Sources/Features/DesignSystem/NotePalette.swift`: seven `NoteColorKey`-keyed entries with independently designed light/dark values (FR-031, no mechanical transparency/brightness transforms), semantic migration mapping (FR-032), contrast-validated metadata; colors are app constants, NOT persisted (data-model.md)
- [X] T008 [P] Create `App/Sources/Features/DesignSystem/NoteCardMetrics.swift`: FR-021 deterministic rules — minCardWidth 180, spacing 12, columns = `max(1, floor((contentWidth+12)/192))`, cardWidth = `(contentWidth − (columns−1)×12) / columns`, height bounds 72–128 (SC-022)
- [X] T009 [P] Create `App/Sources/Features/DesignSystem/AppMetrics.swift`: restrained spacing/typography semantic tokens for cross-window consistency (FR-080/FR-081), preferring system metrics over inflated padding/radius
- [X] T010 Update `App/Sources/Features/NoteWindow/ReadableTheme.swift` to project foreground auto-adjustment (FR-033) using NotePalette actual rendered values instead of source literals (001 FR-042 semantics preserved)
- [X] T011 Add `commands` CommandGroups in `App/Sources/App/StickyNotesApp.swift`: File (new note ⌘N, new from clipboard, region capture, window capture, move-to-Trash ⌘⌫, close ⌘W), Edit (standard + insert todo ⌘⇧T / code block ⌘⇧C), View (search focus ⌘F, sort submenu, show/hide note windows), Window, Help (help, about); actions reuse existing `LibraryModel`/`NoteWindowCoordinator`/`SyncCoordinator` methods — NO new command manager; keyboard-compatible with existing shortcuts (research.md D7/C)
- [X] T012 [P] Accessibility foundation: keyboard-navigation scaffolding for the card grid (arrow-key selection model, Return open, ⌘⌫ move-to-Trash — FR-024), localizable label policy for custom controls (001 FR-180b continuation) in `App/Sources/Features/Library/LibraryModel.swift` + `App/Sources/Features/Shared/`

**Checkpoint**: Foundation ready — palette/metrics/tokens compile, menus work, SC-017 checklist green; user stories can begin.

---

## Phase 3: User Story 1 - 内容优先的 Library (Priority: P1) 🎯 MVP

**Goal**: 单一原生工具栏（新建/搜索/排序/目的地）+ 内容优先自适应卡片网格 + 无底部工具条 + Trash 目的地确认语义（plan Phase 2）。

**Independent Test**: 打开 Library → 只有一条工具栏、无底部栏、无 Quit 入口；工具栏新建/搜索/排序/进入 Trash 全部可用；宽度缩放列数按 FR-021 公式变化。

### Tests for User Story 1 (FIRST — must FAIL before implementation) ⚠️

- [X] T013 [P] [US1] Update `AppTests/GridMetricsTests.swift` to FR-021 formula: deterministic columns at SC-021 breakpoints (≥756→4, ≥564→3, ≥372→2, else 1), card widths per FR-021 formula: 4-column widths assert 180–228; 2-column ≈276 max; 1-column = full width; all boundary widths (372/564/756) and sub-320 clamp asserted deterministically, fractional-boundary widths (exactly 372/564/756 pt) and sub-320 pt clamp (CHK014/CHK035) — MUST FAIL against current 220×160 fixed constants
- [X] T014 [P] [US1] Update `AppTests/CardRenderingTests.swift` to SC-022 density bounds: default-width card height ≤128 pt and ≥72 pt, blank-space ratio ≤20% on a FIXED, repeatable typical-content sample (spec-defined card content profile: title + 2-line preview + modified time — CHK010); measure in the same coordinate space as SC-001 (content area incl. banner-free state — CHK056) — MUST FAIL against current 160 pt card
- [X] T015 [P] [US1] Add UI tests in `AppUITests/CriticalFlowsUITests.swift`: Library shows exactly one toolbar, no bottom bar, no Quit entry in app UI (SC-005/FR-006); zero-state (no notes) and search no-match state remain usable via existing EmptyStateView semantics (CHK003); layout assertion: toolbar height ≤ native toolbar metric and content area ≥80% of window height with sync banner counted into content area (SC-001); create note via toolbar button / ⌘N / global shortcut each ≤1 step (SC-002); with Dock icon hidden, Quit/Settings/Help/About remain reachable via menu-bar interface (Constitution X) — MUST FAIL
- [X] T016 [P] [US1] Add UI tests: search is part of the toolbar single control row (SC-007/FR-003); Search All Notes global shortcut opens Library AND focuses search field; combined states (CHK029): search-while-in-Trash-scope, sort-change-while-searching, destination switch with active query behave per spec.md Edge Cases 组合态条目; IME composition (e.g. pinyin) in the native search field does not break querying (CHK040) — MUST FAIL
- [X] T017 [P] [US1] Write FR-026 confirmation tests in new `AppTests/DeletionConfirmationTests.swift`: move-to-Trash needs NO confirmation (001 FR-014), permanent delete (single) and empty Trash require explicit confirmation with permanent-deletion wording incl. the "30 天可恢复保证不再适用" clause (CHK013) — MUST FAIL

### Implementation for User Story 1

- [X] T018 [US1] Native toolbar feasibility spike: determine whether the MenuBarExtra window supports (a) attached AppKit `NSToolbar` via the existing window probe, or (b) SwiftUI `.toolbar` + `.searchable`; acceptance criteria: toolbar items display, overflow works, keyboard-reachable (incl. Tab/Shift-Tab focus order — CHK004), click-outside-close and 4pt/left-edge positioning do NOT regress (FR-001/001a); record decision (plan.md §14/§15) and proceed with the chosen architecture — blocks T019–T021
- [X] T019 [US1] Implement single native toolbar as the only top-level control row in `App/Sources/Features/Library/MenuBarLibraryScene.swift`: new note (SF Symbol, FR-002a), search, sort popup (001 FR-022 modes, secondary weight, FR-004), Notes/Trash compact destination control (FR-005 (a)); remove stacked header (big new-note block, segmented control, sort row) per spike decision; define and verify toolbar focus order (new → search → sort → destination, CHK004); sort popup shares toolbar-item metrics with new-note/search (same height/inset — CHK012)
- [X] T020 [US1] Replace `App/Sources/Features/Library/LibrarySearchView.swift` with native search (toolbar search field or `.searchable`): system clear/exit behavior, keyboard reachable, single control row (FR-003), IME composition safe (CHK040); result timing unchanged (001 FR-024/024a — FTS5 untouched)
- [X] T021 [US1] Make `LibraryCardGrid` adaptive per FR-021 formula using `NoteCardMetrics` (plan.md §14): progressive column reduction on narrow widths, deterministic formula, default sort by recently modified (001 FR-022); sub-320 pt clamps to 1 column with readable cards (FR-070)
- [X] T022 [US1] Update `App/Sources/Features/Library/NoteCardView.swift` for density (height 72–128, SC-022): FR-020 information priority (title/first line → preview → modified time), no large blank areas, selection state clear but not dominant and NOT color-only (FR-023), hover context actions without layout jump (appear/disappear never change card size, FR-023/CHK036); FR-025 卡片信息字段保留：2 行预览截断、相对/绝对时间边界、待办进度、封面缩略图、冲突/同步警示徽标沿用 CardProjection 语义与 001 规则，仅布局适配、不回归
- [X] T023 [US1] Implement Trash destination: revive `App/Sources/Features/Trash/TrashView.swift` as the Trash destination view with Empty Trash + single permanent-delete confirmations (FR-026) wired into `App/Sources/Features/Library/LibraryModel.swift` trash-scope actions; trash visually subordinate to Notes (SC-006); reuse existing `EmptyStateView` for Library zero-state and search no-match state (CHK003)
- [X] T024 [US1] Remove the footer from `App/Sources/Features/Library/MenuBarLibraryScene.swift` (FR-006): Help/About/Settings/refresh/diagnostics reachable via app menus, toolbar overflow, or contextual menus; Quit appears only in app menu/system; add menu-bar icon dropdown (Settings/About/Help/Quit) reachable when Dock hidden (LSUIElement, Constitution X)
- [X] T025 [US1] Complete the Search All Notes action (research.md D8): global shortcut `searchAll` and `stickynotes://search` deep link now open Library and focus the search field (action identity unchanged, 001 FR-120)
- [X] T026 [US1] Create `App/Sources/Features/Library/SyncAttentionBanner.swift` shell: basic attention-state banner placement above the grid with three-element layout (what happened / local data safe / action), dismissible — full seven-category mapping lands in US5 (FR-010 scaffold)；壳的可关/重现语义以 US5 T052/T056 为验收，本任务仅落位三要素布局与关闭动作骨架
- [X] T027 [US1] Wire keyboard navigation into `LibraryCardGrid`: arrow keys move selection, Return opens, ⌘⌫ moves to Trash (FR-024), integrated with drag-to-reorder in manual sort (001 FR-022a preserved, incl. 1024-gap + 64-renorm regression — CHK039); card grid keyboard focus model distinct from toolbar Tab order (CHK004)

**Checkpoint**: US1 fully functional — single toolbar, no footer, formula grid, Trash confirmations; all US1 tests green.

---

## Phase 4: User Story 2 - 即写即得的独立笔记窗口 (Priority: P1)

**Goal**: 新建即获焦可打字；"Add Block" 降权为插入点上下文控件 + 菜单/键盘；失活外观正确（plan Phase 3）。

**Independent Test**: 新建笔记 → 直接打字无需选块 → 块插入经上下文控件与菜单/键盘可达 → 窗口失活/重激活外观正确。

### Tests for User Story 2 (FIRST — must FAIL before implementation) ⚠️

- [X] T028 [P] [US2] Write FR-042 tests in `AppTests/NoteWindowLifecycleTests.swift`: new note window (from Library / global shortcut / menu / deep link / widget) places keyboard focus near content top; no large unexplained blank between top and first line; typing plain rich text needs no block-type selection (SC-003) — per plan.md §6 this behavior already exists; run as regression verification (pass = baseline; any failure is a real gap to close via T034). MUST-FAIL gate not applicable (documented exception like T003)
- [X] T029 [P] [US2] Write SC-004 tests in `AppTests/BlockPresentationConsistencyTests.swift`: no persistent "Add Block" first-screen control; block insertion reachable via insertion-point context control AND Edit/Insert menu AND keyboard commands (⌘⇧T/⌘⇧C preserved); insertion-control presentation triggers (hover/selection/IME) and hide conditions per CHK008 — MUST FAIL
- [X] T030 [P] [US2] Extend `AppTests/AppearanceIntegrationTests.swift`: inactive note window shows macOS-expected inactive appearance — no inappropriate accent retention on controls, emphasis, or floating controls (FR-045/FR-044); assert verifiable properties (which elements, which accent channels — CHK011) — MUST FAIL

### Implementation for User Story 2

- [X] T031 [US2] Create `App/Sources/Features/Editor/BlockInsertionControl.swift`: subtle insertion-point context control (near cursor line), native presentation (glassEffect MAY per FR-044/FR-061), concrete presentation triggers (cursor-line hover/selection) and hide conditions (pointer leave/blur/IME active — CHK008), appears only when useful, does not obscure content (FR-043; NO "/" command system)
- [X] T032 [US2] Remove the persistent "Add Block" control from `App/Sources/Features/Editor/RichTextBlockView.swift`; expose block insertion via Edit/Insert menu commands + keyboard shortcuts added in T011; all block kinds/behaviors preserved (001 FR-050/050a/050b)
- [X] T033 [US2] Update `App/Sources/Features/NoteWindow/NoteControlsView.swift`: inactive-state appearance driven by `appearsActive` (FR-045), glass presentation for custom controls only where warranted (FR-044/061), hide-on-pointer-leave, no permanent content occlusion（图标用 SF Symbols，禁自定义位图，FR-064）
- [X] T034 [US2] Verify compact-size usability (FR-071): note window remains usable at compact sizes, no unnecessary toolbar exposed; confirm FR-042 focus/blank behavior end-to-end across all creation paths (001 FR-007a); explicit FR-040 regression assertions: standard traffic lights, move/resize/minimize/close semantics unchanged (001 FR-006/007/032)

**Checkpoint**: US2 fully functional — type immediately on create, contextual insertion, correct inactive appearance.

---

## Phase 5: User Story 3 - 克制的笔记配色系统 (Priority: P1)

**Goal**: 七色调色板在浅/深模式分别呈现于颜色控件；FR-031/032/033 全组合达标（常量与测试已在 Phase 2 落地，此处完成用户可见部分）。

**Independent Test**: 浅色与深色下逐色检查对比度；旧笔记颜色迁移后身份保留；自定义颜色原值不变。

### Tests for User Story 3 (FIRST — must FAIL before implementation) ⚠️

- [X] T035 [P] [US3] Write UI tests in `AppUITests/CriticalFlowsUITests.swift`: note color control presents exactly the seven-color palette; custom color (001 FR-040) selectable and preserved — MUST FAIL
- [X] T036 [P] [US3] Write FR-033 combination tests in `AppTests/PaletteContrastTests.swift`: custom color + transparency + appearance/Increase Contrast combinations auto-adjust foreground to threshold (FR-033), color never rejected — MUST FAIL

### Implementation for User Story 3

- [X] T037 [US3] Update the color picker UI in `App/Sources/Features/NoteWindow/NoteControlsView.swift` to present the seven-color palette with per-appearance values from `NotePalette` (FR-030); old color keys map semantically (紫→薰衣草, FR-032); custom color unchanged
- [X] T038 [US3] Light/Dark rendering verification pass (SC-014 partial for palette): every palette color renders with correct per-mode design values; contrast assertions pass end-to-end against real rendering

**Checkpoint**: US3 fully functional — restrained palette, per-mode values, migration mapping, custom color intact.

---

## Phase 6: User Story 4 - 原生质感的设置窗口 (Priority: P2)

**Goal**: 工具栏式标签导航四面板（通用/同步/字体/权限），原生表单惯例，面板高度适配内容，加入既有 vault 首次配置入口（plan Phase 4）。

**Independent Test**: 打开设置 → 四面板工具栏式导航切换；录制全局快捷键并验证冲突反馈；同步面板默认页与高级区；字体中英混排预览；权限状态展示。

### Tests for User Story 4 (FIRST — must FAIL before implementation) ⚠️

- [X] T039 [P] [US4] Update `AppTests/AppLogicTests.swift`: Settings uses native toolbar-style tab navigation (FR-050) with exactly four logical areas (General/Sync/Fonts/Permissions); panel height adapts to content, no fixed blank canvas (FR-051/SC-011) — MUST FAIL
- [X] T040 [P] [US4] Add UI tests in `AppUITests/CriticalFlowsUITests.swift`: four-panel navigation works; each panel renders native form controls — MUST FAIL
- [X] T041 [P] [US4] Update `AppTests/ShortcutConfigurationTests.swift`: recorder conflict semantics (001 FR-121): conflicts reported clearly, never silently replaced, reset/clear works, fully keyboard-operable — MUST FAIL
- [X] T042 [P] [US4] Update `AppTests/FontPreferenceApplicationTests.swift`: single user-facing "note font" concept (primary + system fallback, no implementation typography terms, FR-055); storage key unchanged; meaningful bilingual real-time preview — MUST FAIL
- [X] T043 [P] [US4] Write settings failure-handling tests in `AppTests/AppLogicTests.swift` (spec §Failure & Recovery, CHK031): settings panel load/save failure shows non-blocking localizable notice, user data never overwritten, app continues normally (001 FR-011a semantics extension) — MUST FAIL

### Implementation for User Story 4

- [X] T044 [US4] Replace segmented navigation in `App/Sources/Features/Settings/SettingsView.swift` with `TabView` toolbar-style tabs (Settings scene; macOS 14+ native; FR-050); verify tab-bar overflow behavior at narrow settings-window widths (CHK007); keep NSWindow fallback content in sync
- [X] T045 [US4] Rework General panel: "Show Dock Icon" + all 7 global shortcut items (001 FR-120 unchanged) with native macOS shortcut-preference appearance (current value visible, clear recording state, reset/clear, conflict/error feedback, FR-052)
- [X] T046 [US4] Rework SyncSettingsView default page (FR-053): sync status, provider, last successful sync time, auto-sync toggle, frequency options unchanged (001 FR-152), unlock state (001 FR-162a), primary sync/retry action; errors as readable descriptions per FR-012 mapping input
- [X] T047 [US4] Update `App/Sources/Features/Settings/FontPreferenceView.swift`: single "note font" concept + system fallback, bilingual mixed-language preview (FR-055), default aligned with macOS system typography (001 FR-043 behavior)
- [X] T048 [US4] Update Permissions panel (FR-056): per-permission current status / why needed / dependent features / action to open system flow; unused permissions labeled optional-not-mandatory (Constitution VI); lazy request timing unchanged (001 FR-131/132/133)
- [X] T049 [US4] Align NSWindow fallback path with new tab layout; set panel heights to fit content (FR-051); verify window sizing semantics (research.md D12 note — title-match hack stays for now)
- [X] T050 [US4] Implement the first-configuration "join existing vault" entry (FR-054 + clarify 4, CHK006/CHK033): when no sync configuration exists, SyncSettingsView default page presents both "Configure Sync" and "Join Existing Vault" initial-setup paths; join flow reuses `SyncCoordinator.joinExistingVault` (read-only probe semantics per research.md §6) with the same confirm semantics as the advanced re-entry (T057); daily switching stays "replace repository" (001 FR-154)

**Checkpoint**: US4 fully functional — native tab navigation, native forms, all four panels verified, first-configuration join flow present.

---

## Phase 7: User Story 5 - 同步状态的上下文呈现 (Priority: P2)

**Goal**: 正常态零占位；七类注意态横幅（三要素 + 动作）；多类别优先级确定化；高级区与诊断边界（plan Phase 5）。

**Independent Test**: 正常同步无任何同步 UI；人为断网/改密码 → 上下文状态条出现（人话 + 本地安全 + 重试），无内部错误标识符。

### Tests for User Story 5 (FIRST — must FAIL before implementation) ⚠️

- [X] T051 [P] [US5] Write FR-012 exhaustive mapping tests in new `AppTests/SyncStatusPresentationTests.swift`: every internal error category (ProviderError transient/401/403, vault-locked, offline changes pending, conflictCopiesCreated, historyAgedOutDetected, decryption failure/corrupt manifest/wrong vault/version mismatch) maps deterministically to one of the seven categories (cannotConnect/authFailed/needsUnlock/pendingChanges/conflictCopiesCreated/historyAgedOut/repositoryDamaged); zh-Hans/en both complete; descriptions contain NO internal identifiers, URLs, credentials (FR-011/SC-012); MULTI-category priority (CHK002): when several categories are simultaneously active (e.g. authFailed + historyAgedOut), a deterministic winner is asserted (优先级顺序按 plan.md §9 决议：⑦>③>②>①>⑤>④>⑥) — MUST FAIL
- [X] T052 [P] [US5] Write FR-010 banner semantics tests in new `AppTests/SyncBannerSemanticsTests.swift`: dismiss hides; banner does NOT reappear while state unchanged; a NEW error category re-presents; retry triggers 001 FR-151 manual-sync-equivalent behavior WITHOUT blocking local editing (FR-010a/001 FR-153); retry-fails-again outcome (CHK005): same category persists with re-presentation per FR-010, no dismissal churn; SUCCESS paths (CHK030): retry success clears the banner to zero-footprint, vault unlock success clears needsUnlock, re-authentication success clears authFailed — MUST FAIL
- [X] T053 [P] [US5] Add UI test in `AppUITests/CriticalFlowsUITests.swift`: seeded sync attention state renders banner with three elements + action, no internal identifiers visible — MUST FAIL
- [X] T054 [P] [US5] Write FR-054 advanced-area tests in `AppTests/SyncCompositionTests.swift`: advanced maintenance operations (replace repository/remove configuration/export config/export diagnostics) live in a separate Advanced area (SC-013); join-existing-vault has initial-setup (T050) + advanced re-entry paths (CHK033); destructive operations visually/semantically distinct and confirmed (001 FR-154 semantics preserved); FR-163 warning standard style, not panel-dominant — MUST FAIL

### Implementation for User Story 5

- [X] T055 [US5] Implement `App/Sources/Features/Library/SyncStatusPresentation.swift`: deterministic pure-function mapping (SyncCoordinator state + SyncSummary flags + sanitized ProviderError codes → seven categories with title/detail/action/dismissible per data-model.md), incl. the multi-category priority resolution asserted in T051; viewConflicts action opens the existing conflict-copy note window (001 ConflictCopyView/NoteWindowCoordinator reuse — no new view)
- [X] T056 [US5] Complete `SyncAttentionBanner.swift`: all seven categories rendered with three elements (what happened / local data safe / action), dismiss semantics per FR-010, non-blocking retry (FR-010a), retry-failure persistence (CHK005), VoiceOver announcement of three elements (spec Accessibility), normal-state zero footprint (FR-007)；横幅图标用 SF Symbols（FR-064）
- [X] T057 [US5] Reorganize `App/Sources/Features/Settings/SyncSettingsView.swift` advanced area: replace repository / remove configuration / join existing vault (recovery re-entry, consistent with T050) / export sync configuration / export diagnostic package with confirmations (FR-054); daily repo switching stays "replace" (001 FR-154)
- [X] T058 [US5] Enforce diagnostic boundary: internal identifiers and diagnostics ONLY in advanced diagnostics/export-diagnostic-package experience (FR-011/FR-191); verify sanitized logs contain no note content/paths/secrets

**Checkpoint**: US5 fully functional — seven-category banner with deterministic priority, dismiss semantics, advanced area separated, diagnostic boundary enforced.

---

## Phase 8: User Story 6 - 窗口缩放、键盘、菜单与系统行为 (Priority: P2)

**Goal**: Liquid Glass 仅功能/控制层；缩放/键盘/系统行为（Reduce Transparency/Motion、Increase Contrast/Show Borders、VoiceOver）全合规（plan Phase 6）。

**Independent Test**: 320–1600 pt 缩放列数/溢出正确；纯键盘完成核心流程；开启 Reduce Transparency 与 Increase Contrast 自定义控件仍可读；VoiceOver 走查主要流程。

### Tests for User Story 6 (FIRST — must FAIL before implementation) ⚠️

- [ ] T059 [P] [US6] Write system-behavior assertion tests in new `AppTests/SystemBehaviorEnvironmentTests.swift`: custom controls remain understandable under Reduce Transparency / Reduce Motion / Increase Contrast / Show Borders (environment-key-driven appearance assertions; FR-062/063/SC-015); Reduce-Motion governs custom control appear/disappear animations (CHK038) — MUST FAIL
- [ ] T060 [P] [US6] Add UI tests: Library window scaled 320–1600 pt — column count follows FR-021, secondary toolbar items move into system overflow without compressing content, no duplicated navigation controls (FR-070) — MUST FAIL
- [ ] T061 [P] [US6] Add keyboard-only workflow UI test: create/search/select/open/delete entirely via keyboard; every important toolbar command reachable from menu bar (SC-017/FR-072); toolbar focus order verified (new → search → sort → destination, CHK004) — MUST FAIL
- [ ] T062 [P] [US6] Write SC-010/SC-019 glass-usage assertions (code-review style): no decorative glass, no manual blur/gradient/border/shaders emulating Liquid Glass where system behavior exists; glass only on functional/control layer; cards/content surfaces are NOT glass (SC-009) — MUST FAIL

### Implementation for User Story 6

- [ ] T063 [US6] Integrate guarded platform polish: `visibilityPriority(_:)` (#available macOS 26.1) and `effectIsInteractive` (#available macOS 27.0) where applicable; record usage in `Documentation/toolchain.md` (CI toolchain Xcode 26.x safety)
- [ ] T064 [US6] Apply `glassEffect(_:in:)` + `GlassEffectContainer` to custom interactive controls per plan.md §7 Usage Map (insertion control, floating controls MAY); NEVER on note content/cards/editor surfaces; no glass-on-glass; clear glass not used as default (FR-060/061)
- [ ] T065 [US6] Implement narrow-width overflow behavior: secondary toolbar items into system overflow (FR-070); navigation controls never duplicated; cards stay ≥180 pt readable (FR-020)
- [ ] T066 [US6] VoiceOver pass on all custom controls: card selection, insertion control, sync banner, shortcut recorder — explicit localized labels and states (001 FR-180b); selection/state never color-only (001 FR-044)
- [ ] T067 [US6] Final native-behavior review: display-scale checks, active/inactive across surfaces, D12 window-title hack cleanup only if low-risk (else record remaining)

**Checkpoint**: US6 fully functional — glass scoping, scaling, keyboard, accessibility, system behaviors verified.

---

## Phase 9: User Story 7 - 迁移与兼容 (Priority: P3)

**Goal**: 升级后既有笔记/颜色/同步配置/加密/快捷键/字体/权限/偏好全部有效；无迁移（plan §10）。

**Independent Test**: 用 001 既有 fixtures（含旧六色/自定义颜色/Trash 笔记/同步配置/偏好）启动新版，全部数据与配置原样可用。

### Tests for User Story 7 (FIRST — must FAIL before implementation) ⚠️

- [ ] T068 [P] [US7] Write migration fixture test in new `AppTests/MigrationCompatibilityTests.swift`: 001 schema fixtures (v1/v2, old six-color + custom-color notes + Trash notes + blocks) open in new UI with all content/color/opacity/font-size/pin/window-position preserved (FR-090/SC-020/SC-025) — MUST FAIL until fixture-verified
- [ ] T069 [P] [US7] Write old-vault sync-config fixture test in `AppTests/SyncCompositionTests.swift`: existing repo config, encrypted data, and unlock semantics unchanged after upgrade; no re-entry of repo config required (001 FR-150/154/162a) — MUST FAIL
- [ ] T070 [P] [US7] Write preservation tests: global shortcuts and font preference survive upgrade (`AppTests/ShortcutConfigurationTests.swift`, `AppTests/FontPreferenceApplicationTests.swift`); screen-recording/accessibility permission states preserved — no re-request, no lost known state (FR-090) — MUST FAIL

### Implementation for User Story 7

- [ ] T071 [US7] Fix any compatibility issues surfaced by fixture tests (expected: none — presentation-only redesign; verify and document in `Documentation/toolchain.md` or feature quickstart.md); confirm zero schema/keychain/contract changes (contracts/ README assertion)

**Checkpoint**: US7 verified — all fixture tests green; upgrade path fully compatible.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: 全量回归、性能、视觉 QA、本地化、文档收尾（plan Phase 7）。

- [ ] T072 [P] Full regression: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore` + `xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'` — all suites green (StickyCore 92, AppTests 44, AppUITests ≥5 — count grows with new UI tests); regression checklist includes 001 FR-011a resilience: Library open/sort/search failure → no crash, no data loss, non-blocking localized notice (spec §Failure & Recovery); WidgetExtension behavior unchanged (001 FR-110a/111/112)
- [ ] T073 [P] Performance regression (SC-024/FR-091): `PerformanceBaselineTests`/`SearchPerformanceTests`/`KeystrokeLatencyTests` green; 10k-note grid virtualization scrolling + search ≤200 ms verified (FR-094a/FR-072b non-regression, CHK042); no idle CPU from new presentation layer (SC-006); assert search start-update latency (query change → first update ≤100 ms, 001 FR-024a) in SearchPerformanceTests; if micro-timing unsupported, record waiver and spot-check manually
- [ ] T074 [P] Manual visual QA matrix per plan.md §12: light/dark, active/inactive, system accent, Reduce Transparency/Motion, Increase Contrast/Show Borders, display scale, 320 pt & wide Library, compact note window, multi-window, keyboard-only, VoiceOver walkthrough; itemize and check the SC-018 Apple HIG walkthrough list (CHK054 — which HIG items, per-surface), cross-window visual-language coherence check (FR-082), and record results in quickstart.md; core capture-loop timing (open Library → create → type → close → reopen → search-find, ≤30 s, 001 SC-011 / SC-023) verified manually
- [ ] T075 [P] Localization completeness: zh-Hans/en strings complete for all new UI (banner three elements, palette, menus, settings, confirmations) via `AppTests/LocalizationCompletenessTests.swift`（先核实 001 是否存在；不存在则本任务新建之）+ String Catalog; no internal identifiers in any user-facing string (FR-012)
- [ ] T076 [P] Documentation updates: finalize API usage record in `Documentation/toolchain.md` (incl. `visibilityPriority`/`effectIsInteractive` guards); reconcile plan.md/research.md with implementation reality; mark 001 spec FRs superseded: 001 FR-002a→003 FR-020/FR-021; 001 FR-004→003 FR-002/002a/003/004/005/006/007; 001 FR-030a→003 FR-040/FR-041; 001 FR-031→003 FR-044/FR-045; 001 FR-040a→003 FR-030/031/032 (CHK062) so cross-feature traceability stays truthful
- [ ] T077 Final verification: SC-001..SC-025 checklist pass; `git diff --exit-code` after `xcodegen generate` (no project drift); feature artifacts (spec/plan/tasks) consistent via `/speckit.analyze`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — baseline first
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational
  - US1 → US2 → US3 (P1 order); then US4, US5, US6 (P2); US7 (P3)
  - US5 depends on US1 banner shell (T026); US6 depends on US1 toolbar + US2 floating controls + US4 settings surfaces
- **Polish (Phase 10)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Foundational only (palette/metrics/menus). Contains gating spike T018.
- **US2 (P1)**: Foundational menus (T011) — insertion commands. Independent of US1.
- **US3 (P1)**: Foundational palette constants/tests (T004/T005/T007). Independent of US1/US2.
- **US4 (P2)**: Foundational menus. Independent.
- **US5 (P2)**: US1 banner shell (T026) + US4 join-flow entry (T050). Sync engine untouched. FR-054 高级区重组跨 US4（T050 首配入口）+ US5（T057 高级区），对应 plan §15 Phase 4/5，非缺口。
- **US6 (P2)**: US1 toolbar, US2 floating controls, US4 settings.
- **US7 (P3)**: All stories (validates the whole redesigned app against old data).

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Presentation models before views; views before integration
- Story complete and green before moving to next priority

### Parallel Opportunities

- Phase 1: T003 [P] alongside T001/T002
- Phase 2: tests T004–T006 [P] in parallel; implementations T007–T009 [P], then T010/T011/T012
- US1: tests T013–T017 [P] in parallel; spike T018 first, then T019–T021 dependent, T022–T027 [P] after spike
- US2: tests T028–T030 [P]; T031→T032 sequential, T033/T034 [P]
- US3: tests T035/T036 [P]; T037→T038
- US4: tests T039–T043 [P]; T044 first, then T045–T050 [P] (T050 pairs with US5 T057)
- US5: tests T051–T054 [P]; T055 first, then T056–T058 [P]
- US6: tests T059–T062 [P]; T063–T067 largely [P]
- US7: tests T068–T070 [P]; T071 last
- Polish: T072–T076 [P]

---

## Parallel Example: User Story 1

```bash
# Launch all US1 tests together (must fail before implementation):
Task: "Update GridMetricsTests to FR-021 formula"
Task: "Update CardRenderingTests to SC-022 density"
Task: "UI tests: single toolbar / no footer / no Quit"
Task: "UI tests: search in toolbar + searchAll focus + combined states"
Task: "DeletionConfirmationTests (FR-026)"

# After spike T018, launch surface work together:
Task: "Single native toolbar in MenuBarLibraryScene"
Task: "Replace LibrarySearchView with native search"
Task: "Adaptive grid via NoteCardMetrics"
Task: "NoteCardView density + selection states"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (baseline + API freeze)
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: US1 (Library) — spike first
4. **STOP and VALIDATE**: US1 independently (single toolbar, formula grid, no footer, Trash confirmations)
5. Demo-able increment: the Library looks like a macOS 27 first-party surface

### Incremental Delivery

1. Setup + Foundational → native design foundation live
2. US1 Library → test → demo (MVP)
3. US2 Note window → test → demo
4. US3 Palette → test → demo
5. US4 Settings → test → demo
6. US5 Sync UX → test → demo
7. US6 System behavior → test → demo
8. US7 Migration → test → release-verify
9. Polish → full regression + QA

### Parallel Team Strategy

- Team completes Setup + Foundational together
- After Foundational: Developer A = US1, Developer B = US2, Developer C = US3 (all P1)
- P2 stories (US4–US6) as capacity allows; US7 last

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to user story for traceability
- Each user story independently completable and testable
- Verify tests FAIL before implementing; commit after each task or logical group (conventional commits per AGENTS.md)
- StickyCore + WidgetExtension = zero changes (REUSE) — any task touching `Packages/StickyCore/**` or `WidgetExtension/**` violates the plan
- No migration, no new third-party dependencies, no new permissions (Constitution VI/XIII)
- Build/test commands must use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` prefix (quickstart.md)
- 任务命名协调（001 遗留，见 quickstart.md）：`StickyNotes.xcodeproj` 二进制已提交，`project.yml` 为事实源——源码变更后用 `xcodegen generate` 重新生成并验证无漂移
- design.md checklist gaps resolved in this revision: CHK002 (T051/T055), CHK004 (T018/T019/T061), CHK006/CHK033 (T050), CHK029 (T016), CHK031 (T043), CHK039 (T027), CHK040 (T016/T020), CHK062 (T076); spec-level gaps (CHK003/CHK013/CHK014/CHK054/CHK056) closed via task-level assertions referencing spec semantics — if a deeper spec rewrite is needed, do it via `/speckit.clarify` before `/speckit.implement`
