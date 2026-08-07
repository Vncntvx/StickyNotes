# Requirements Quality Checklist: UX, Interaction & Editor Integrity

**Purpose**: Validate the *quality of the written requirements* (not the
implementation) for the user-facing interaction, editor, window-management,
appearance, accessibility, localization, widgets, shortcuts, permissions, and
deletion-lifecycle domain of the macOS Sticky Notes spec — the area governed by
constitutional principles II (native macOS & SwiftUI-first), V (structured
editor integrity), X (consistent, accessible, reversible UX), XI (performance),
and I (focused sticky-notes product). This is a "unit test suite for the
English": each item asks whether a requirement is complete, clear, consistent,
measurable, and traceable.
**Created**: 2026-08-07
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [data-model.md](../data-model.md) · [contracts/](../contracts/)
**Domain**: UX / Interaction / Editor / Windows / Appearance / Accessibility / Widgets / Shortcuts / Permissions / Deletion lifecycle
**Depth**: Comprehensive (release-gate rigor)
**Traceability**: Strong — every item cites a FR/SC/contract/constitution anchor

## Requirement Completeness

- [x] CHK001 - Are requirements specified for the exact visual positioning of the menu-bar library window relative to the menu bar (pixel offset, alignment, animation behavior on open/dismiss)? [Completeness, Spec §FR-001, Constitution II]
- [X] CHK002 - Is the card-grid layout fully specified — card dimensions, number of columns, spacing, responsive behavior at different window widths, scroll behavior, and empty-state presentation? [Completeness, Gap, Spec §FR-002]
- [X] CHK003 - Are all library affordances from FR-004 enumerated with their expected entry points (menu items, toolbar buttons, keyboard shortcuts, drag-and-drop targets) so no affordance is ambiguously reachable? [Completeness, Spec §FR-004]
- [X] CHK004 - Are requirements defined for the visual appearance of a note window that "looks like a lightweight sheet of note paper" — border style, corner radius, shadow, title-bar presence, background texture? [Completeness, Gap, Spec §FR-030]
- [X] CHK005 - Are all upper-area controls from FR-031 enumerated with their individual visibility timing, interaction model (toggle/button/menu/picker), and keyboard-accessibility fallback? [Completeness, Spec §FR-031]
- [ ] CHK006 - Are requirements specified for the visual presentation of each block category (rich text, todo, code, file-reference, embedded image, screenshot) in the editor — spacing, borders, background, inline vs block display? [Completeness, Gap, Spec §FR-050]
- [ ] CHK007 - Are requirements defined for the card-grid card content beyond the field list in FR-020 — specifically the truncation behavior of body previews, the format of last-modified time (relative vs absolute), and the visual design of todo-completion progress? — truncation/time resolved by FR-020a; the visual design of todo-completion progress is still open [Completeness, Gap, Spec §FR-020]
- [x] CHK008 - Are requirements specified for the screenshot viewer's exact interaction model — zoom increment, pan gesture, keyboard navigation between screenshots, caption-editing entry point, and viewer window type (panel vs window vs sheet)? [Completeness, Gap, Spec §FR-095]
- [ ] CHK009 - Are requirements defined for the visual design and interaction model of the file-reference card — icon size, metadata layout, availability-status indicator design, and relink-UI flow? [Completeness, Gap, Spec §FR-100]
- [X] CHK010 - Are requirements specified for the Trash UI — list layout, sort order, restoration confirmation, permanent-delete confirmation, and visual distinction between Trash/permanent-deleted/recovered-conflict-copy/active states? [Completeness, Spec §FR-175, US6]
- [X] CHK011 - Are requirements defined for the Settings UI structure — section organization, entry points from menu-bar vs Dock, and the relationship between Settings, sync settings, permission settings, and shortcut settings? [Completeness, Gap, Spec §FR-008]
- [X] CHK012 - Are all six widget forms from FR-110 individually specified with their exact size class, content layout, interaction affordances, refresh behavior, and placeholder/loading states? [Completeness, Spec §FR-110]
- [X] CHK013 - Are requirements defined for the keyboard-first operation model promised by the constitution — specifically the full list of keyboard commands for every essential action (create, open, close, search, sort, delete, restore, indent, outdent, reorder blocks, toggle todo, cycle colors, toggle always-on-top)? [Completeness, Gap, Constitution X]
- [ ] CHK014 - Are requirements specified for the empty-state behavior of every surface — empty library, empty search results, empty Trash, no notes eligible for widgets, no sync configured? [Completeness, Gap]
- [ ] CHK015 - Are requirements defined for the visual feedback when an async operation is in progress (saving, searching, syncing, generating thumbnail, capturing screenshot) — progress indicator type, cancelability, and non-blocking behavior? [Completeness, Gap, Spec §FR-152]

## Requirement Clarity

- [X] CHK016 - Is "compact card grid inspired by the Windows 11 Sticky Notes experience" clarified with specific measurable properties (card aspect ratio, grid gap, columns at default width) rather than relying on a subjective external reference? [Clarity, Ambiguity, Spec §FR-002]
- [X] CHK017 - Is "lightweight sheet of note paper" clarified with measurable visual properties (opacity range, border width, shadow radius) rather than a subjective adjective? [Clarity, Ambiguity, Spec §FR-030]
- [X] CHK018 - Is "most window controls SHOULD remain hidden until the pointer enters the upper area" clarified with the exact trigger region (height in points, full-width vs centered), the show/hide animation, and the behavior when focus moves away? [Clarity, Gap, Spec §FR-031]
- [x] CHK019 - Is "short body preview" on note cards quantified with a character/line limit or truncation rule? [Clarity, Gap, Spec §FR-020]
- [X] CHK020 - Is "readable presentation of long lines via wrapping or horizontal scrolling" for code blocks resolved to a single choice (wrapping OR scrolling) or a user-toggleable option, rather than an ambiguous "or"? [Clarity, Ambiguity, Spec §FR-080]
- [X] CHK021 - Is "promptly" in "Search results MUST update promptly as the query changes" (FR-024) quantified with a debounce or latency target, or is SC-005's 200ms the binding interpretation? [Clarity, Spec §FR-024/SC-005]
- [X] CHK022 - Is "unobtrusive" in "Formatting tools SHOULD remain unobtrusive" (FR-052) clarified with a measurable criterion (appear-on-selection delay, auto-dismiss timeout, max visible controls)? [Clarity, Ambiguity, Spec §FR-052]
- [X] CHK023 - Is "meaningful content" in FR-012/FR-013 defined with an explicit enumeration of what counts (non-whitespace text, title, todo, image, screenshot, code block, file reference) so the auto-discard vs preserve boundary is unambiguous? [Clarity, Spec §FR-012/FR-013]
- [X] CHK024 - Is "first meaningful content" for the generated summary (FR-021) defined with a selection rule (first non-empty line? first sentence? max character count?) so two implementations produce the same summary? [Clarity, Gap, Spec §FR-021]
- [X] CHK025 - Are the exact built-in color values for Yellow, Pink, Purple, Blue, Green, Gray specified (hex/sRGB) so the appearance is reproducible and contrast-tested? [Clarity, Gap, Spec §FR-040]
- [X] CHK026 - Is the transparency adjustment range quantified (min/max opacity, step size, default) rather than "adjustable"? [Clarity, Gap, Spec §FR-041]
- [x] CHK027 - Is the text-size adjustment quantified (min/max point sizes, step, default, per-note vs global) rather than "each note MAY use its own text size"? [Clarity, Gap, Spec §FR-043]
- [X] CHK028 - Is the "additional actions" item in FR-031's control list enumerated (what actions are available beyond the listed ones)? [Clarity, Gap, Spec §FR-031]
- [X] CHK029 - Are the widget interaction affordances in FR-111 specified as MAY-per-action or as a definitive list of which actions each widget form supports? [Clarity, Spec §FR-110/FR-111]
- [X] CHK030 - Is "clear, specific, and non-alarming" for permission explanations (FR-134) clarified with tone guidelines, max length, or example wording so the requirement is testable? [Clarity, Ambiguity, Spec §FR-134]

## Requirement Consistency

- [X] CHK031 - Do the note-lifecycle states in spec.md (active, in Trash, permanently deleted, recovered conflict copy) align exactly with the US6 acceptance scenarios, the Edge Cases, and FR-175's distinguishability requirement? [Consistency, Spec §FR-014/FR-175/US6]
- [X] CHK032 - Does the "close ≠ delete" guarantee (FR-006) align consistently with the auto-discard rule (FR-012) — is the boundary between "close hides" and "close MAY auto-remove" unambiguous? [Consistency, Spec §FR-006/FR-012]
- [X] CHK033 - Do the window-restoration requirements align: FR-007 (MUST NOT auto-restore) vs FR-032 (MUST remember size/position) vs FR-033 (MUST move inaccessible window) — is the behavior for "remembered but not auto-restored" position consistent? [Consistency, Spec §FR-007/FR-032/FR-033]
- [X] CHK034 - Are the Always-on-Top requirements consistent across FR-031 (toggle in upper area), FR-034 (per-note), US3/AC3 (independent per note), and the Edge Cases? [Consistency, Spec §FR-031/FR-034/US3]
- [X] CHK035 - Does the Dock-icon requirement (FR-008) consistently list the same set of menu-bar-reachable functions (Settings, Help, About, sync status, Quit) across FR-004, FR-008, US8/AC5, and the Edge Cases? [Consistency, Spec §FR-004/FR-008/US8]
- [X] CHK036 - Are the Markdown-conversion trigger requirements consistent between FR-060 (patterns recognized), FR-061 (when conversion fires), US5/AC1-2 (acceptance scenarios), and the Edge Cases (Chinese IME)? [Consistency, Spec §FR-060/FR-061/US5]
- [X] CHK037 - Do the todo-identity requirements (FR-071) align consistently across the editor (US4/AC2), widgets (US8/AC2), sync (US10), and the Edge Cases (widget-toggle-while-editing)? [Consistency, Spec §FR-071/US4/US8/US10]
- [X] CHK038 - Are the screenshot-capture requirements consistent between FR-091 (capture modes), FR-092 (static only), FR-093 (metadata), US7/AC1-2 (acceptance), and the Edge Cases (unavailable title/icon)? [Consistency, Spec §FR-091/FR-092/FR-093/US7]
- [X] CHK039 - Are the file-reference requirements consistent between FR-100 (card display), FR-101 (actions), FR-102 (drag-out), FR-103 (missing file), US4/AC4-6, and the Edge Cases (moved file)? [Consistency, Spec §FR-100/FR-101/FR-102/FR-103/US4]
- [X] CHK040 - Do the widget-privacy requirements (FR-112) align consistently with the constitution's per-note widget-privacy guarantee (Principle VI) and the Edge Cases (widget-ineligible note)? [Consistency, Constitution VI, Spec §FR-112]
- [X] CHK041 - Are the permission requirements consistent between FR-130 (what permissions), FR-131 (when requested), FR-132 (screen-recording denied), FR-133 (accessibility denied), US7/AC6, US8/AC6, and the Edge Cases? [Consistency, Spec §FR-130/FR-131/FR-132/FR-133]
- [X] CHK042 - Does the "no auto-restore of windows" requirement (FR-007) align with the "remembered WindowState" entity and the "move inaccessible window" requirement (FR-033) without contradiction? [Consistency, Spec §FR-007/FR-033, data-model §WindowState]

## Acceptance Criteria & Measurability

- [X] CHK043 - Can SC-001 (menu-bar opens ≤150ms warm) be objectively measured, and are the measurement conditions specified (hardware class, data volume, what "warm" means)? [Measurability, Spec §SC-001]
- [X] CHK044 - Can SC-002 (card content ≤300ms) be measured independently of SC-001, and is "card content" defined (first card visible? all cards rendered? thumbnails loaded?)? [Measurability, Spec §SC-002]
- [X] CHK045 - Can SC-003 (note window ≤200ms) be measured, and is the measurement trigger specified (click create? keyboard shortcut? deep link?)? [Measurability, Spec §SC-003]
- [X] CHK046 - Can SC-004 ("no visible lag") be objectively measured, or does it need a quantified frame-time or keystroke-to-glyph latency target? [Measurability, Gap, Spec §SC-004]
- [X] CHK047 - Can SC-009 (100% of P1 acceptance scenarios demonstrable without P2/P3) be verified as a testable gate, and is "without P2/P3 configured" defined (no sync? no widgets? no screenshots?)? [Measurability, Spec §SC-009]
- [X] CHK048 - Can SC-011 (core capture loop <30s without help) be objectively measured, and is the measurement protocol specified (fresh install? existing notes? keyboard only?)? [Measurability, Spec §SC-011]
- [X] CHK049 - Are the acceptance scenarios for each user story independently testable — i.e., can US1 be verified without US2-US10 being implemented, per SC-009? [Measurability, Spec §SC-009, US1-US10]
- [X] CHK050 - Is the "strikethrough" requirement for completed todos (FR-070, FR-182) measurable as a specific visual property (line position, thickness, color) rather than just "strikethrough"? [Measurability, Spec §FR-070/FR-182]
- [X] CHK051 - Can "text and controls remain readable" (FR-041, FR-042, FR-182) be objectively verified — is a contrast ratio target (WCAG-like) specified for custom colors and transparency combinations? [Measurability, Gap, Spec §FR-041/FR-042/FR-182]

## Scenario Coverage (UX Flows)

- [X] CHK052 - Are Primary scenario requirements complete for the full note-capture loop: open library → create note → type → close → reopen → search → find (US1 + US2 + US6)? [Coverage, Spec §US1/US2/US6, SC-011]
- [X] CHK053 - Are Alternate scenario requirements defined for creating a note via global shortcut (not via library) and via clipboard contents (FR-120)? [Coverage, Spec §FR-120]
- [X] CHK054 - Are Alternate scenario requirements defined for opening a note via widget deep link (not via library) and the window-uniqueness behavior that follows? [Coverage, Spec §FR-110/FR-111, contracts/deep-links.md]
- [ ] CHK055 - Are Exception scenario requirements defined for: note window fails to open, library fails to dismiss, search returns no results, sort switch fails, manual reorder fails? [Coverage, Gap]
- [X] CHK056 - Are Recovery scenario requirements defined for: user accidentally closes a note with unsaved content (auto-save guarantee), user accidentally deletes a note (Trash restore), user empties Trash by mistake (is there any recovery?)? [Coverage, Spec §FR-006/FR-014, Gap]
- [X] CHK057 - Are Non-Functional scenario requirements defined for editor performance under stress: very long notes (1000+ blocks), rapid keystroke bursts, large paste operations, simultaneous block insertions? [Coverage, Gap, Constitution XI]
- [X] CHK058 - Are requirements defined for the first-launch experience — empty library, no notes, first note creation, permission prompts not yet shown? [Coverage, Gap]
- [X] CHK059 - Are requirements defined for the multi-window management experience — 10+ note windows open simultaneously, window cycling, window-layering with Always-on-Top, focus behavior? [Coverage, Gap, Spec §FR-005/FR-034]
- [X] CHK060 - Are requirements defined for the transition between online and offline states from the user's perspective — does the UI change, does sync status update, does the user see a notification? [Coverage, Gap, Spec §FR-142/FR-152]

## Edge Case Coverage

- [ ] CHK061 - Is the edge case specified where the menu-bar icon is clicked while a modal sheet is open (Settings, Save As, etc.) — does the library still toggle, or is the modal dismissed first? [Edge Case, Gap, Spec §FR-009]
- [X] CHK062 - Is the edge case specified where a note window is open and the user deletes that note from the library or Trash — does the window close, show a stale state, or block deletion? [Edge Case, Gap, Spec §FR-006/FR-014]
- [ ] CHK063 - Is the edge case specified where two notes have byte-identical first-line text — do their generated summaries collide, and is the card distinguishable? [Edge Case, Spec §Edge Cases, FR-021]
- [X] CHK064 - Is the edge case specified where a note has 100+ todo items — does the editor scroll, does the card show "99+ completed", does sync handle the payload? [Edge Case, Gap, Spec §FR-070]
- [X] CHK065 - Is the edge case specified where a code block contains 10,000+ characters — does wrapping/scrolling handle it, does copy work, does the card preview truncate? [Edge Case, Gap, Spec §FR-080]
- [X] CHK066 - Is the edge case specified where a file-reference card's file is on an external volume that is currently unmounted — does the card show "unavailable", does relink work after remount? [Edge Case, Gap, Spec §FR-103]
- [X] CHK067 - Is the edge case specified where the user captures a screenshot but the captured application closes before the note is saved — is the screenshot still preserved? [Edge Case, Gap, Spec §FR-091/FR-092]
- [X] CHK068 - Is the edge case specified where a widget is configured for a note that is then deleted, trashed, or becomes conflicted — does the widget show a placeholder, error, or stale data? [Edge Case, Spec §Edge Cases, FR-112]
- [X] CHK069 - Is the edge case specified where the global shortcut for "create note" is pressed while another app's modal dialog is open — does the shortcut fire, or is it suppressed? [Edge Case, Gap, Spec §FR-120]
- [X] CHK070 - Is the edge case specified where a note's custom color is set to the same hue as the system accent color — does the note remain visually distinguishable from system UI? [Edge Case, Gap, Spec §FR-040/FR-042]
- [X] CHK071 - Is the edge case specified where the user pastes a very large image (50MB+) — does the editor handle it, does the card grid show a thumbnail, does sync handle the asset? [Edge Case, Gap, Spec §FR-090/FR-094a]
- [X] CHK072 - Is the edge case specified where the user drags a file into a note that is already open on another display — does the file-reference block appear in the correct window? [Edge Case, Gap, Spec §FR-005/FR-100]

## Non-Functional Requirements (UX/Performance)

- [X] CHK073 - Are performance requirements specified for the card-grid scroll behavior — does it use lazy loading, virtualization, or bounded rendering, and is the scroll frame rate targeted? [Non-Functional, Gap, Constitution XI, SC-002/SC-008]
- [X] CHK074 - Are performance requirements specified for the editor typing latency under various conditions (large note, active search, IME composition, paste)? [Non-Functional, Spec §SC-004, Constitution XI]
- [X] CHK075 - Are concurrency requirements specified for the editor when a widget toggles a todo on the same note that is being edited — is there a conflict-detection or merge requirement at the UX level? [Non-Functional, Spec §FR-071, Edge Cases]
- [ ] CHK076 - Are accessibility performance requirements specified — does VoiceOver navigation through a large note have a target response time? [Non-Functional, Gap, Constitution X/XI]
- [X] CHK077 - Are requirements specified for the memory footprint of the card grid when displaying 10,000 notes with thumbnails — is there a bounded memory target? [Non-Functional, Gap, Constitution XI, SC-005/SC-008]
- [X] CHK078 - Are requirements specified for the window-animation behavior on open/close/dismiss — is animation optional (Reduce Motion), and is the default animation duration targeted? [Non-Functional, Constitution X, Spec §FR-003/FR-009]
- [X] CHK079 - Are requirements specified for the battery impact of the menu-bar app when idle — does SC-006's "no sustained CPU" translate to a measurable energy-impact target? [Non-Functional, Spec §SC-006, Constitution XI]

## Accessibility & Internationalization

- [ ] CHK080 - Are VoiceOver labels and actions specified for every interactive element — or is the requirement generic ("meaningful accessibility labels") without enumerating which elements need them? [Completeness, Gap, Spec §FR-180, Constitution X]
- [X] CHK081 - Are keyboard-navigation requirements specified for every surface — library grid navigation, card activation, sort switching, Trash navigation, Settings tabbing, editor block navigation, todo reorder — or is it generic ("keyboard navigation")? [Completeness, Gap, Spec §FR-180, Constitution X]
- [X] CHK082 - Are requirements specified for focus management when windows open/close — does focus move to the new note window, does it return to the library, does it return to the previously focused app? [Completeness, Gap, Spec §FR-005/FR-006]
- [X] CHK083 - Are requirements specified for the accessibility of the upper-area hover controls (FR-031) — since FR-181 says "no essential action via hover only," are keyboard alternatives enumerated for every hover-revealed control? [Completeness, Spec §FR-031/FR-181, Constitution X]
- [ ] CHK084 - Are requirements specified for VoiceOver announcement behavior when async operations complete (save, sync, capture, thumbnail generation, file relink)? [Completeness, Gap, Spec §FR-180]
- [X] CHK085 - Are requirements specified for the accessibility of drag-and-drop operations (todo reorder, block reorder, file drag-in/out, screenshot drag-out) — are keyboard alternatives defined? [Completeness, Gap, Constitution X, Spec §FR-070/FR-100/FR-102]
- [X] CHK086 - Are requirements specified for Increased Contrast behavior — does the app use system-defined high-contrast colors, does it override custom note colors, does it adjust transparency? [Clarity, Gap, Spec §FR-042/FR-182, Constitution X]
- [X] CHK087 - Are requirements specified for Reduce Motion behavior — which animations are suppressed, what replaces them (instant transition, fade), and is the behavior testable? [Clarity, Gap, Spec §FR-180, Constitution X]
- [X] CHK088 - Are requirements specified for the font-fallback behavior when a user-selected font lacks glyphs for Chinese or English characters — is the fallback chain deterministic, and is the behavior visible to the user? [Clarity, Gap, Spec §FR-043, Constitution X]
- [X] CHK089 - Are requirements specified for the localization of every user-facing string — are string-catalog keys enumerated, are there requirements for text expansion/contraction in Chinese vs English layout? [Completeness, Gap, Spec §FR-180, plan §Localization]
- [X] CHK090 - Are requirements specified for the accessibility of the screenshot viewer — zoom, pan, navigation, caption editing — for VoiceOver and keyboard users? [Completeness, Gap, Spec §FR-095, Constitution X]
- [X] CHK091 - Are requirements specified for the accessibility of the file-reference card — open, reveal, copy path, relink, move, remove — for VoiceOver and keyboard users? [Completeness, Gap, Spec §FR-101, Constitution X]
- [X] CHK092 - Are requirements specified for the accessibility of widgets — does VoiceOver read widget content, can widget actions be triggered via Switch Control, and does widget content respect Reduce Motion? [Completeness, Gap, Spec §FR-110/FR-112, Constitution X]

## Widgets, Shortcuts & Permissions (UX Surface)

- [X] CHK093 - Are requirements specified for the widget refresh policy — how often does each widget form refresh, does it refresh on note change, and what happens when the app is not running? [Completeness, Gap, Spec §FR-110/FR-111]
- [X] CHK094 - Are requirements specified for the widget deep-link routing — does opening a note from a widget bring the app to the foreground, and does it respect the Dock-icon policy? [Consistency, Spec §FR-008/FR-009, contracts/deep-links.md]
- [ ] CHK095 - Are requirements specified for the widget-eligibility toggle UX — where in the note UI is the setting, is it on the upper-area control bar, and is it keyboard-accessible? [Completeness, Gap, Spec §FR-031/FR-112]
- [X] CHK096 - Are requirements specified for the global-shortcut configuration UI — how does the user set a shortcut, how are conflicts displayed, and what happens when a shortcut is already taken by the system? [Completeness, Gap, Spec §FR-120/FR-121]
- [X] CHK097 - Are requirements specified for the shortcut-conflict detection behavior — does it check at registration time, at configuration time, or both, and does it suggest alternatives? [Clarity, Gap, Spec §FR-121]
- [X] CHK098 - Are requirements specified for the permission-prompt timing and wording — exactly when does the screen-recording prompt appear, what does it say, and does it explain why before requesting? [Completeness, Spec §FR-131/FR-132/FR-134, Constitution VI]
- [X] CHK099 - Are requirements specified for the permission-denied UX — what does the screenshot-capture UI show when screen-recording is denied, and is the "open System Settings" action a button or a link? [Clarity, Gap, Spec §FR-132]
- [X] CHK100 - Are requirements specified for the Dock-icon toggle UX — is it a Settings toggle, does it take effect immediately, and does the menu-bar interface update in response? [Completeness, Gap, Spec §FR-008]

## Deletion Lifecycle & Reversibility (UX Surface)

- [X] CHK101 - Are requirements specified for the delete-action confirmation behavior — is there a confirmation dialog, is it optional, and does it differ for single-note vs bulk delete? [Completeness, Gap, Spec §FR-014, Constitution X]
- [X] CHK102 - Are requirements specified for the permanent-delete confirmation — is it a separate action from Trash delete, does it require a second confirmation, and is the wording distinct? [Completeness, Gap, Spec §FR-014/FR-175]
- [X] CHK103 - Are requirements specified for the Trash-empty behavior — is there an "Empty Trash" action, does it confirm, and does it explain the 30-day vs immediate distinction? [Completeness, Gap, Spec §FR-014]
- [X] CHK104 - Are requirements specified for the visual labeling of a recovered conflict copy in the library — what does the label say, where is it displayed, and does it link to the original? [Clarity, Gap, Spec §FR-171/FR-175]
- [X] CHK105 - Are requirements specified for the undoability of destructive actions — is deleting a note undoable, is emptying Trash undoable, is permanent delete undoable? [Completeness, Gap, Constitution X]
- [X] CHK106 - Are requirements specified for the conflict-copy comparison UX — how does the user compare the original and the conflict copy, is there a side-by-side view, and can the user merge manually? [Completeness, Gap, Spec §FR-171]

## Editor Integrity (Constitution V Surface)

- [X] CHK107 - Are requirements specified for the cursor-placement behavior after every Markdown transformation — where does the cursor land after heading/bullet/todo/inline conversion, and is it testable? [Clarity, Gap, Spec §FR-061, Constitution V]
- [X] CHK108 - Are requirements specified for the block-boundary behavior — what happens when the user presses Backspace at the start of a block, Enter at the end, or tries to merge two blocks? [Completeness, Gap, Constitution V]
- [X] CHK109 - Are requirements specified for the paste behavior of different content types — plain text, rich text (supported marks), rich text (unsupported marks), Markdown source, image, file — and is the conversion behavior for each specified? [Completeness, Gap, Spec §FR-050/FR-053, Constitution V]
- [X] CHK110 - Are requirements specified for the link-detection behavior — does auto-link happen on type, on paste, on space, on Enter, and does it handle URLs with unusual characters? [Clarity, Gap, Spec §FR-050, Constitution V]
- [X] CHK111 - Are requirements specified for the Undo/Redo stack behavior across block boundaries — does Undo cross block boundaries, does it restore deleted blocks, and is the stack per-note or per-block? [Clarity, Gap, Spec §FR-051/FR-062, Constitution V]
- [X] CHK112 - Are requirements specified for the IME composition interaction with block boundaries — what happens when the user presses Enter during composition, or when composition spans a block boundary? [Completeness, Gap, Spec §FR-063, Constitution V/X]
- [X] CHK113 - Are requirements specified for the editor's behavior when a block is empty — does it auto-delete, does it show a placeholder, does it merge with the next block? [Completeness, Gap, Constitution V]
- [x] CHK114 - Are requirements specified for the selection behavior across multiple blocks — can the user select text spanning blocks, does copy produce rich text or plain text, and does delete remove whole blocks? [Completeness, Gap, Constitution V]

## Constitution Alignment (This Domain)

- [X] CHK115 - Does every UX requirement trace to a constitutional principle (II native macOS, V editor integrity, X accessible/reversible, XI performance, I focused product)? [Traceability, Constitution II/V/X/XI/I, plan §Constitution Check]
- [X] CHK116 - Is it confirmed that no UX requirement contradicts the "focused sticky-notes product" principle (I) — no drawing, no handwriting, no PM features, no live monitoring, no plugins? [Traceability, Constitution I, Spec §Non-goals]
- [X] CHK117 - Is it confirmed that the SwiftUI-first principle (II) is not violated by any UX requirement — are AppKit fallbacks documented with evidence where needed? [Traceability, Constitution II, plan §Editor architecture]
- [X] CHK118 - Is it confirmed that the "reversible UX" principle (X) is satisfied for every destructive action — delete, permanent delete, empty Trash, move original file, remove block? [Traceability, Constitution X, Spec §FR-014/FR-102]
- [X] CHK119 - Is it confirmed that the "keyboard-first" principle (X) is satisfied — are there requirements stating that no essential action is available ONLY via pointer? [Traceability, Constitution X, Spec §FR-181]
- [X] CHK120 - Is it confirmed that no Complexity Tracking exception is used to bypass accessibility, reversibility, or editor-integrity requirements in this domain? [Traceability, Constitution §Governance, plan §Complexity Tracking]

## Notes

- This checklist tests the **quality of the written requirements**, not whether
  the implementation works. Items phrased as "Are X defined/specified…?" and
  "Is X quantified/clarified…?" validate completeness/clarity/consistency/
  measurability/coverage; they are NOT verification steps.
- Anchors: `[Spec §FR-xxx/SC-xxx]`, `[plan §<section>]`, `[data-model §<entity>]`,
  `[Contracts §<file>]`, `[Constitution §<principle>]`, `[Gap]` (missing
  requirement), `[Ambiguity]`, `[Conflict]`, `[Assumption]`, `[Dependency]`.
- Focus: menu-bar library / note windows / editor / appearance / accessibility /
  localization / widgets / shortcuts / permissions / deletion lifecycle /
  editor integrity (constitutional II/V/X/XI/I). Depth: Comprehensive (release
  gate). Strong traceability: every item carries ≥1 reference.
- Items flagged `[Gap]` indicate a requirement that should be added or made
  explicit before implementation; they are not implementation TODOs.
- Overlap with `data.md` is intentional but scoped: this checklist probes the
  *user-visible interaction* aspects of entities and states; `data.md` probes
  the *data-shape* aspects. Where an item could fit either, it is placed here
  only if it tests UX/interaction quality.
- Overlap with `security.md` is intentional but scoped: this checklist probes
  the *user-facing privacy UX* (widget-eligibility toggle, permission prompts,
  diagnostic-bundle export UI); `security.md` probes the *encryption/privacy*
  mechanism.
