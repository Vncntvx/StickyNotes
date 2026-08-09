# Design Package Quality Checklist: macOS 27 原生质感重设计（Liquid Glass）

**Purpose**: Validate the quality, clarity, completeness, and consistency of the full design package (spec.md + plan.md + tasks.md + data-model.md) — unit tests for requirements writing, NOT implementation verification
**Created**: 2026-08-09
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [tasks.md](../tasks.md) · [data-model.md](../data-model.md)

## Requirement Completeness

- [x] CHK001 Are the seven sync status categories (FR-012) specified with their trigger inputs (engine state / SyncSummary flags / error codes), and is the mapping guaranteed exhaustive for every current internal error code? [Completeness, Spec §FR-012]
- [x] CHK002 Is the priority/aggregation behavior specified when MULTIPLE sync error categories are simultaneously active (e.g., auth failure + history aged out) — which banner wins, in what order? [Gap, Spec §FR-010/FR-012]
- [x] CHK003 Are requirements defined for the Library zero-state (no notes at all) and the search no-match state, or is their survival from 001 explicitly declared in 003? [Coverage, Gap]
- [x] CHK004 Is the keyboard focus-order requirement defined for the toolbar controls (new/search/sort/destination) and the card grid (Tab/Shift-Tab vs arrow keys), or does it rely on an unstated default? [Coverage, Spec §FR-024/FR-072]
- [x] CHK005 Are requirements specified for the banner retry action's failure outcome (retry fails again — same category persists, new presentation rules per FR-010)? [Coverage, Gap, Spec §FR-010a]
- [x] CHK006 Is the "加入既有 vault" initial-setup flow specified as a first-launch experience (when it appears, what it asks), or only the re-entry path? [Gap, Spec §FR-054]
- [x] CHK007 Are requirements defined for the settings panels under narrow settings-window widths (tab bar overflow behavior), or only for Library scaling (FR-070)? [Gap]

## Requirement Clarity

- [x] CHK008 Is "微妙添加控件"（FR-043 插入点控件）defined with concrete presentation triggers (hover/selection/IME), positioning, and hide conditions, beyond "插入点附近"? [Clarity, Spec §FR-043/FR-044]
- [x] CHK009 Is the deferral of palette hex values to implementation stage explicit and GATED by mandatory FR-031/001 FR-042 contrast verification (no unverifiable fixed values in spec)? [Clarity, Spec §FR-031/Assumptions]
- [x] CHK010 Is SC-022's "典型内容" sample defined well enough to be repeatable (which card content profile), given it drives a ≤20% blank-space assertion? [Measurability, Spec §SC-022]
- [x] CHK011 Is FR-045's "不保留不恰当的强调色"（inactive window）specified with verifiable properties (which elements, which accent channels), or is it subjective-only? [Measurability, Spec §FR-045]
- [x] CHK012 Is FR-004's sorting-control "视觉权重不高于新建与搜索" operationalized (size/position/emphasis rules), or does it rely on judgment? [Ambiguity, Spec §FR-004]
- [x] CHK013 Is the empty-Trash vs single-permanent-delete confirmation wording specified (what each dialog states, per FR-026), including the "30 天可恢复保证不再适用" clause? [Clarity, Spec §FR-026]
- [x] CHK014 Is FR-021's column formula unambiguous for fractional boundaries (content width exactly 372/564/756 pt) and for sub-320 pt widths (hard minimum, or clamp)? [Clarity, Spec §FR-021/FR-070]
- [x] CHK015 Is the "有未同步更改"（信息性）category's dismissibility and re-presentation rule distinguished from other categories (FR-010 applies to all?), or is dismissibility per-category undefined? [Ambiguity, Spec §FR-010/FR-012]

## Requirement Consistency

- [x] CHK016 Do FR-005 (destination control option a/b) and the Assumptions section agree on the default (toolbar destination (a)) with a bound on when (b) sidebars may be chosen? [Consistency, Spec §FR-005/Assumptions]
- [x] CHK017 Does the conditional preference-key-rename migration requirement (Data & Migration Implications) stay consistent with plan.md's zero-key-rename decision, or is the conditional requirement dead weight? [Consistency, Spec §Data & Migration, plan §10]
- [x] CHK018 Are the seven categories (FR-012), clarify-session decision 1, and data-model.md `SyncStatusCategory` enum names one-to-one consistent (no renumbered/renamed classes across artifacts)? [Consistency, Spec §FR-012/data-model.md]
- [x] CHK019 Do FR-043 (no "/" command), clarify decision 2, and plan.md T031/T032 agree on the insertion mechanism set (context control + menu + keyboard)? [Consistency, Spec §FR-043/plan §15]
- [x] CHK020 Does SC-001's "内容区 ≥ 80% 窗口高度" hold when a sync banner is present (banner occupies content area — threshold must survive banner + toolbar)? [Consistency, Spec §SC-001/FR-010]
- [x] CHK021 Are the preserved-001 semantics (menu-bar positioning FR-001/001a, Trash 30-day FR-014, capture FR-131–134, sync FR-150–174) referenced consistently, with no 003 requirement silently overwriting them? [Consistency]
- [x] CHK022 Do tasks.md phases and plan.md §15 phases map one-to-one, and does every tasks.md story carry the plan's completion criteria (no orphan tasks)? [Consistency, plan §15/tasks.md]

## Acceptance Criteria Quality

- [x] CHK023 Can SC-021 breakpoints (≥756→4, ≥564→3, ≥372→2 columns) be verified deterministically from FR-021's formula, and do they match the formula's outputs exactly? [Measurability, Spec §SC-021/FR-021]
- [x] CHK024 Are SC-009 ("卡片为非玻璃内容表面") and SC-019 ("无手工模糊/透明度模拟玻璃") verifiable by code review/assertion rather than visual judgment? [Measurability, Spec §SC-009/SC-019]
- [x] CHK025 Is SC-017's menu-checklist scope bounded (which commands are "重要工具栏命令") so the checklist test is enumerable and stable? [Clarity, Spec §SC-017/FR-072]
- [x] CHK026 Are US1–US7 independent-test statements each tied to at least one acceptance scenario or SC number (traceable verification per story)? [Acceptance Criteria, Spec §User Stories]
- [x] CHK027 Is SC-023 (核心捕获循环 ≤30 s) a regression carry-over with a defined measurement method, or is it unverifiable in practice? [Measurability, Spec §SC-023]
- [x] CHK028 Does the spec's "Required Tests" section cover all seven categories of FR-012 (exhaustive), and are zh-Hans/en both mandatory there? [Acceptance Criteria, Spec §Required Tests/FR-012]

## Scenario Coverage

- [x] CHK029 Are Alternate-scenario requirements present for: search while in Trash scope, sort change while searching, and destination switch with active query (combined states)? [Coverage, Gap]
- [x] CHK030 Are Recovery-scenario requirements defined for: banner retry success (state clears, banner disappears per FR-010), vault unlock success, and re-authentication success? [Coverage, Gap, Spec §FR-010a]
- [x] CHK031 Are Exception-scenario requirements present for settings-panel load/save failure (non-blocking, no data overwrite) per Failure & Recovery Behavior — and does plan.md assign implementation tasks? [Coverage, Spec §Failure & Recovery]
- [x] CHK032 Is the conflict-copy "查看" action's destination specified (which view, how reached), given ConflictCopyView exists in 001? [Coverage, Spec §FR-012 ⑤]
- [x] CHK033 Is the "首次配置流程"（join existing vault, FR-054）covered in the plan's phases and tasks, or does it exist only in spec? [Coverage, plan §15/tasks.md]
- [x] CHK034 Are multi-window scenarios covered in requirements (multiple note windows + Library simultaneously; per-window inactive states)? [Coverage, Gap, Spec §FR-040]

## Edge Case Coverage

- [x] CHK035 Are extreme-width edges defined: window narrower than 320 pt, and cards at exact 180 pt minimum with long titles (truncation rules per FR-020)? [Edge Case, Spec §FR-021/FR-070]
- [x] CHK036 Is the hover-action no-layout-jump rule (FR-023) specified for ALL hover-revealed actions (context menu, color, pin, delete) or only some? [Edge Case, Spec §FR-023]
- [x] CHK037 Is the edge case "banner closed, new error category arrives" (FR-010 reappear) present in both spec Edge Cases AND data-model.md state flow? [Edge Case, Spec §Edge Cases/data-model.md]
- [x] CHK038 Are Reduce-Motion requirements defined for custom control appear/disappear animations (FR-044 floating controls), or does FR-062/063 leave animation behavior unstated? [Edge Case, Gap, Spec §FR-062/FR-063]
- [x] CHK039 Is the "手动排序 + 1024-gap renorm"（001 FR-022a）survival explicitly covered for the redesigned grid (drag-to-reorder in FR-024)? [Edge Case, Gap]
- [x] CHK040 Is IME/input-method behavior specified for the native search field and card grid keyboard nav (Chinese input composition while typing in search)? [Edge Case, Gap]

## Non-Functional Requirements

- [x] CHK041 Are performance targets for ALL FR-091 surfaces (menu-bar warm start, card ≤300 ms, new note ≤200 ms, keystroke <16 ms, 10k search ≤200 ms, idle zero CPU) mapped to regression suites in tasks.md (PerformanceBaselineTests/SearchPerformanceTests/KeystrokeLatencyTests)? [NFR, Spec §FR-091/tasks.md T073]
- [x] CHK042 Is the 10k-note grid virtualization requirement (FR-094a thumbnails / FR-072b todos) explicitly preserved against redesign regression? [NFR, Spec §Performance Expectations]
- [x] CHK043 Are accessibility NFRs (FR-031 contrast thresholds, FR-180b labels, non-color-only states, VoiceOver three-element banner) complete across ALL redesigned surfaces (Library/card/note/settings/banner/recorder)? [NFR, Spec §Accessibility Implications]
- [x] CHK044 Is the privacy/diagnostic NFR boundary (no internal identifiers, URLs, credentials in FR-012 strings; FR-191 export field list unchanged) consistent between spec, data-model.md, and tasks.md T058? [NFR, Spec §FR-011/FR-191]
- [x] CHK045 Are zero-new-permission and lazy-request NFRs (001 FR-131–134) restated or referenced in the redesigned Permissions panel requirements (FR-056)? [NFR, Spec §FR-056]
- [x] CHK046 Is the no-handmade-glass NFR (FR-062) enforceable as a code-review gate, and does plan.md §7 Usage Map enumerate every surface where glass MAY/NOT appear? [NFR, Spec §FR-062/plan §7]

## Dependencies & Assumptions

- [x] CHK047 Is the assumption "MenuBarExtra window supports native toolbar" (plan spike T018) bounded with acceptance criteria and a fallback decision path in both plan and tasks? [Assumption, plan §18/tasks.md T018]
- [x] CHK048 Is the macOS 26.0 deployment + macOS 27 target-behavior assumption consistent across spec (Out-of-Scope), plan §4, and tasks.md T002 (availability guards)? [Assumption, plan §4]
- [x] CHK049 Is the assumption that 001 fixtures remain valid (no migration) validated by a dedicated test task (tasks.md T068–T070), not just asserted? [Assumption, tasks.md T068]
- [x] CHK050 Are the clarified decisions (7 categories, no "/", no confirm-on-move, join-vault placement, tab navigation) recorded in spec.md Clarifications and honored by every downstream task? [Dependency, Spec §Clarifications]
- [x] CHK051 Is the dependency "US5 depends on US1 banner shell (T026)" explicit in tasks.md, and does spec FR-010's banner requirement not conflict with US5's phased delivery? [Dependency, tasks.md §User Story Dependencies]
- [x] CHK052 Is the App-Group placeholder naming issue (`group.local.stickynotes.placeholder`) documented as a known out-of-feature item rather than silently assumed fixed? [Assumption, plan §18]

## Ambiguities & Conflicts

- [x] CHK053 Does "就近横幅或内联"（FR-010）leave the banner placement genuinely open in spec while plan.md fixes it — is the plan's choice (grid-top banner) marked as a decision, not silently assumed? [Ambiguity, Spec §FR-010/plan §6]
- [x] CHK054 Is SC-018 ("Apple HIG 走查清单") itemized anywhere (which checklist items), or is it a black-box criterion? [Ambiguity, Spec §SC-018] — closed 2026-08-09: SC-018 itemized as SC-018a–i (窗口外壳/工具栏/菜单/导航/表单/搜索/内容分层/反模式排除/系统行为), each mapped to existing FRs; execution remains T074/T079 manual walkthrough recording PASS/FAIL per surface in quickstart.md
- [x] CHK055 Does FR-020's "首个有意义行" duplicate or diverge from 001 FR-021 summary rules — is the boundary (title vs first-line vs summary) resolved? [Conflict, Spec §FR-020/FR-025]
- [x] CHK056 Are "内容区"（SC-001）and "卡片空白占比"（SC-022）measured against the same coordinate space (with/without banner, scrollbars), or could the two assertions conflict on the same layout? [Conflict, Spec §SC-001/SC-022]
- [x] CHK057 Is the D12 window-title-match hack (settings/help window fallback) documented as known-technical-debt with a no-block status, in both research.md and plan.md? [Ambiguity, research.md §2.1/plan §2]

## Traceability

- [x] CHK058 Does every tasks.md task reference FR/SC/US identifiers, and does every spec FR map to ≥1 task (reverse traceability — no orphan requirements)? [Traceability, tasks.md]
- [x] CHK059 Is the cross-feature reference convention ("001 FR-0xx") uniform across spec/plan/tasks/data-model (no bare FR numbers that collide with 001 numbering)? [Traceability, Spec §Assumptions]
- [x] CHK060 Are plan.md TDRs (Technical Decision Records) traceable to the spec requirements they serve (each decision cites FR/SC)? [Traceability, plan §16]
- [x] CHK061 Is the spec's required platform-API validation recorded as an explicit task (T002) with a documentation output (toolchain.md), per Required Tests? [Traceability, Spec §Required Tests/tasks.md T002]
- [x] CHK062 Are the 001 requirements superseded by this feature (001 FR-002a/004/030a/031/040a per checklist requirements.md Notes) marked in 001 spec, so cross-feature traceability stays truthful? [Traceability, Gap] — closed 2026-08-09: 001 spec.md lines 569/578/780/786/825 carry `[SUPERSEDED by 003 ...]` markers for FR-002a/FR-004/FR-030a/FR-031/FR-040a respectively (T076)

## Notes

- 本清单校验的是规格/计划/任务三件套的**书写质量**（要求完备、清晰、一致、可测、可追溯），非实现正确性；实现验证见 tasks.md 各故事独立测试。
- 任务级缺口已在 2026-08-09 tasks.md 修订中闭环：CHK002（T051/T055 多类别优先级）、CHK004（T018/T019/T061 焦点序）、CHK006/CHK033（T050 首次配置加入 vault）、CHK029（T016 组合态）、CHK031（T043 设置失败处理）、CHK039（T027 1024-gap 回归）、CHK040（T016/T020 搜索 IME）、CHK062（T076 001 失效 FR 标记）；其余 CHK 为规格级写作质量项，若需深化规格请走 `/speckit.clarify`。
- 既有 `requirements.md`（specify 阶段）保留不动；本文件为设计包阶段新增。
- 2026-08-09 设计包重评估（analyze 修正 + clarify 1 项决策后）：60/62 通过；CHK054（SC-018 HIG 逐项清单）待 T074 实现期逐项列明后勾选，CHK062（001 失效 FR 标记）待 T076 实现期编辑 001 spec 后勾选。
