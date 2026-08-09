# UX Requirements Quality Checklist: 独立笔记窗口原生镀铬与自适应重设计

**Purpose**: Validate the UX requirements in spec.md for completeness, clarity, consistency, measurability, and coverage — before implementation
**Created**: 2026-08-10
**Feature**: [spec.md](../spec.md)

**Note**: This checklist tests the REQUIREMENTS, not the implementation. Every item asks whether the specification itself is well-written, complete, unambiguous, and ready for implementation planning.

## Requirement Completeness

- [x] CHK001 Is the empty-note window-title fallback (note with neither manual title nor content) explicitly specified, or only decided in plan.md §12? [Gap, Spec §FR-003]
- [x] CHK002 Are requirements specified for the in-editor title field (its presence, position, focus behavior, and empty→nil editing semantics) that replaces the removed NoteControlsView title field? [Gap, Spec §FR-003]
- [ ] CHK003 Are window-title update timing requirements specified (live during typing vs debounced; when the first content line changes for untitled notes)? [Gap, Spec §FR-003]
- [x] CHK004 Is the net-new image-insertion capability (no `.image` block creation path exists today) explicitly scoped in the spec, with its behavior and acceptance defined — not just listed among relocated actions? [Gap, Spec §FR-010]
- [x] CHK005 Are requirements specified for preserving the existing ⌥C/⌥O/⌥T keyboard stepping shortcuts after NoteControlsView removal? [Gap, Spec §FR-029]
- [ ] CHK006 Is the requirement defined for the window background strip's opacity treatment (unified content layer, no seam at transparency < 100%)? [Gap, Spec §FR-025]
- [ ] CHK007 Are requirements specified for resizing the window while a popover or menu is open? [Gap, Coverage, Spec §FR-014]
- [ ] CHK008 Are lifecycle requirements specified for the close→reopen path (window must not resurrect with stale state) at the requirement level, or only in plan.md/contracts? [Gap, Spec §FR-031]

## Requirement Clarity

- [ ] CHK009 Is "恢复合理默认" (Appearance reset) specified with concrete default values (which color key, which opacity)? [Clarity, Spec §FR-008]
- [x] CHK010 Is the minimum window height quantified unambiguously — FR-017a says "约 120–160 pt", a range rather than a single enforceable value? [Ambiguity, Spec §FR-017a]
- [x] CHK011 Is the "current editor insertion point" defined precisely (caret in rich-text block → split; focus in special block → after block; none → append), or does FR-010's wording leave the mapping to planning? [Clarity, Spec §FR-010]
- [x] CHK012 Is the "contextual control group" for formatting (FR-012) specified with its anchor, position relative to selection, and dismissal semantics? [Ambiguity, Spec §FR-012]
- [ ] CHK013 Does the spec define what formatting applies to when no text is selected (typing attributes for subsequent input vs disabled)? [Gap, Spec §FR-012]
- [ ] CHK014 Are the semantic content-inset values (compact/regular) quantified in the spec, or only in plan.md §8? [Clarity, Spec §FR-019]

## Requirement Consistency

- [x] CHK015 Do FR-015a (priority model: title truncates last, Pin last to overflow) and FR-015b (220–240: truncated title + Pin + chevron directly visible) agree on every element's status at extreme narrow width? [Consistency, Spec §FR-015a/015b]
- [x] CHK016 Is the transition of title editing from the controls row (001 behavior) into the editor content stated consistently across FR-003 and the Clarifications section (no residual "title stays in toolbar" wording)? [Consistency, Spec §FR-003]
- [x] CHK017 Is the explicit "More" toolbar item (FR-006/FR-015a) consistent with FR-011's guidance that low-frequency actions live in "native menus or system overflow" — is the coexistence of an explicit More item and the system chevron reconciled in the spec? [Consistency, Spec §FR-006/011/015a]
- [x] CHK018 Do FR-010 (insert at current insertion point) and the existing editor architecture (append-only block ordering) conflict — is the caret-split behavior explicitly required or silently assumed? [Conflict, Spec §FR-010]
- [x] CHK019 Is the opacity treatment consistent between FR-008/FR-025 (content-layer alpha, no window.alphaValue) and the titlebar-strip requirement in FR-025 (color shows through translucent toolbar glass)? [Consistency, Spec §FR-008/025]

## Acceptance Criteria Quality

- [x] CHK020 Can SC-005/SC-006 ("note content visually dominates", "top chrome substantially less visual weight") be objectively measured, or are they subjective judgments without a comparison protocol? [Measurability, Spec §SC-005/006]
- [x] CHK021 Is SC-012 ("feels native on macOS 27") verifiable — is an evaluation protocol (criteria list, comparison baseline) defined in the spec? [Measurability, Spec §SC-012]
- [ ] CHK022 Are per-width acceptance expectations (which actions directly visible vs overflowed at 220/320/480/640/800/1200/2000+) stated in the spec as requirements, or only in plan.md §9.1? [Gap, Spec §FR-015b/017]
- [ ] CHK023 Is the "title remains directly visible (truncating)" criterion at 220–240 pt verifiable given system-controlled truncation — is a minimum meaningful title visibility defined? [Measurability, Spec §FR-015b]

## Scenario Coverage

- [ ] CHK024 Are requirements defined for the inactive-window state of the contextual formatting row and floating controls (spec FR-027 covers window-level; does it cover floating UI)? [Coverage, Spec §FR-027]
- [ ] CHK025 Are IME/Chinese-composition requirements defined for contextual formatting and insertion (behavior during marked text)? [Gap, Coverage, Spec §FR-012/028]
- [ ] CHK026 Are exception-flow requirements defined for async insertion (screenshot capture / file selection) when the editor loses focus or the window closes mid-flow? [Coverage, Exception Flow, Spec §FR-010]
- [x] CHK027 Are requirements defined for multiple note windows of very different sizes visible simultaneously with independent toolbar/state behavior? [Coverage, Spec §FR-027/SC-014]
- [ ] CHK028 Are requirements defined for note transparency at the 40% minimum interacting with toolbar/glass legibility (worst-case legibility state)? [Coverage, Edge Case, Spec §FR-025]

## Edge Case Coverage

- [x] CHK029 Are long-title + narrow-window requirements specified (title truncation priority relative to toolbar actions, no control displacement)? [Edge Case, Spec §FR-003/015a]
- [x] CHK030 Are requirements specified for the minimum-height window state (editor scrolling, toolbar usability)? [Edge Case, Spec §FR-017a]
- [ ] CHK031 Is the fallback behavior specified when the system overflow chevron cannot physically accommodate Pin at 220 pt (system-enforced limitation vs FR-015b guarantee)? [Edge Case, Spec §FR-015b]
- [x] CHK032 Are requirements specified for display-scale/screen-change behavior of the new chrome (retains frame-correction semantics)? [Edge Case, Spec §FR-031]

## Non-Functional Requirements

- [x] CHK033 Are performance requirements specified for continuous resizing (no jank, no editor/toolbar object-graph rebuilds, no polling)? [Gap, NFR, Spec §Performance Expectations]
- [x] CHK034 Are accessibility requirements specified for overflow-menu items (labels, toggle state of Pin in overflow)? [Coverage, Spec §FR-029]
- [x] CHK035 Are Reduce Transparency / Increase Contrast requirements specified for the custom glass formatting surface specifically (not just window-level)? [Coverage, Spec §FR-029/035]
- [x] CHK036 Is the macOS 26 vs 27 API availability/fallback matrix specified at the requirement level (not only in research.md/plan.md)? [Completeness, Spec §FR-034/035]

## Dependencies & Assumptions

- [ ] CHK037 Is the assumption documented that NSToolbar renders correctly on the standard note window despite the abandoned MenuBarExtra toolbar spike? [Assumption, Spec §Assumptions]
- [ ] CHK038 Is the dependency on selection observation (currently absent from RichTextView) acknowledged in the spec's dependency/assumption statements? [Dependency, Gap, Spec §FR-012/Assumptions]
- [ ] CHK039 Are assumptions documented for system-overflow visual behavior differences between macOS 26 and 27? [Assumption, Spec §Assumptions]

## Ambiguities & Conflicts

- [ ] CHK040 Is the "directly visible at 220–240 pt" guarantee (FR-015b) reconcilable with "system can reasonably accommodate" (FR-015) — is the boundary between product guarantee and system discretion defined? [Ambiguity, Spec §FR-015/015b]
- [x] CHK041 Does the spec distinguish the window-level Insert (command-oriented, FR-010) from BlockInsertionControl (spatial inline, 003 FR-043) with explicit non-overlapping definitions? [Clarity, Spec §FR-010]
- [x] CHK042 Are all terms of art ("overflow", "contextual", "appearance", "pin") used consistently with a single meaning throughout the spec? [Terminology, Spec §Global]

## Notes

- Traceability: 42/42 items carry explicit spec references or [Gap]/[Ambiguity]/[Conflict]/[Assumption] markers (≥80% target met).
- Re-validation 2026-08-10 (post-remediation): 24/42 items pass against current spec.md. Resolved by remediation edits: CHK001/002 (FR-003), CHK005 (FR-029), CHK010 (FR-017a), CHK011/018 (FR-010), CHK017 (FR-011), CHK020/021 (SC-005a/SC-011).
- Remaining 18 unchecked items fall into three classes: (a) deliberate plan-level decisions that spec intentionally leaves to planning — CHK014 (inset values, FR-019 semantic states), CHK022 (per-width matrix, operationalization of FR-015a/b), CHK012 position detail (deferred in FR-012), CHK023 (system-controlled title truncation); (b) implementation facts documented in plan/contracts but not promoted to spec — CHK003 (title update timing), CHK006 (background-seam unification), CHK008 (unregister-on-close), CHK009 (reset defaults), CHK013 (typing-attributes path), CHK026 (async insertion fallback), CHK037/038 (toolbar viability / selection-observation dependencies); (c) genuine spec gaps for follow-up consideration — CHK007 (popover-open resize), CHK024 (inactive floating UI), CHK025 (IME during formatting), CHK028 (40%-opacity × glass legibility), CHK031 (chevron-fit fallback at 220 pt), CHK039 (macOS 26 vs 27 overflow visuals), CHK040 (FR-015b guarantee vs system discretion).
- Class (b)/(c) items can be promoted into spec.md via a future /speckit.clarify pass if they must become requirements; currently none blocks implementation planning.
