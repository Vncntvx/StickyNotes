# Plan Superseded History — macOS Sticky Notes

> **本目录为历史记录**：后续 `speckit.plan` / `speckit-tasks` /
> `speckit-implement` 默认无需阅读本目录；如需追溯某决定的演变过程再查阅。
>
> 以下内容为 plan.md 中被当前正文取代或已过时的历史记录（2026-08-07 归档）。
> 归档依据：artifact-compaction-report.md §4/§5。所有内容均为**移动**而非
> 复制——plan.md 当前版本已不含以下文字。

## 一、2026-08-07 clarification propagation 记录（原 plan.md 引用块）

以下六个引用块记录了 `/speckit-clarify` 会话成果向 plan 的传播过程。其内容
已全部编码为 spec.md 的正式 FR 并落入 plan.md 当前正文相应章节，此处仅为
审计留档。

### 1. 两个 `/speckit-clarify` 会话（FR-154/FR-162a/FR-174/FR-191/wrong-vault + FR-022a/FR-023a/FR-072a/FR-090a/FR-094a/FR-140a/FR-152a/FR-160a/b/c/d）

Sixteen spec clarifications have been folded into this plan. The first five
(FR-154 repository replacement, FR-162a remember-unlock lifetime, FR-174
long-offline tombstone reconciliation, FR-191 diagnostic-bundle content
boundary, and the wrong-vault-selected edge case) sharpen existing decisions
without altering the architecture. The next eleven (FR-022a sort-key
gap=1024/renorm-at-<64, FR-023a FTS5 external-content mode, FR-072a todo
maxDepth=6, FR-090a assets as independent encrypted sync objects with
SHA-256 + partial-failure retry, FR-094a 256px thumbnail longest edge,
FR-140a 5s bounded busy timeout, FR-152a 2-4s sync debounce, FR-160a
meaningful-metadata positive enumeration, FR-160b observable-leakage bound,
FR-160c Argon2id production minimums ≥19 MiB/≥2 iter/≥1 lane, FR-160d
exhaustive fail-closed input list) promote previously illustrative or
plan-level values into binding spec requirements. The architecture is
unchanged; the values now cite their binding FR.

### 2. UX-gap propagation（FR-014a / SC-004a）

A `checklists/ux.md` coverage review (CHK058) identified the first-launch
experience as an undefined requirement; it is now binding in spec.md as
**FR-014a** (empty library with a clear create-first-note call to action; no
permission prompts on first launch unless the user invokes a feature requiring
them; sync-status area shows "not configured" rather than an error when sync
is unconfigured; a brief, dismissible onboarding hint explaining auto-save and
the menu-bar-primary model, never shown again after the first note is
created). The same review promoted "no visible lag" (SC-004) into a measurable
bound, **SC-004a** (keystroke-to-glyph latency <16 ms during normal editing,
including with Chinese IME composition active, measured via OSLog
signposts/Instruments). These are UI/UX-facing requirements with no impact on
the data model, contracts, or sync protocol; reflected in research.md R28/R29.

### 3. 第三次 `/speckit-clarify` 会话（FR-012a / FR-160e / FR-022a Trash-restore / FR-162a launch+toggle）

Five additional ambiguities were resolved and encoded in spec.md as **FR-012a**
(meaningful-text definition for empty-note auto-removal: ≥1 non-whitespace
Unicode character in the title or any rich-text block, OR the presence of any
todo/image/screenshot/code-block/file-reference block; a single character
qualifies, whitespace-only does not), **FR-160e** (wrong-password unlock
attempts MUST NOT be rate-limited/throttled/lockout-bounded; Argon2id KDF cost
is the rate limiter; no cached password/derived key), and expansions to
**FR-022a** (Trash-restore resets sort-key to max+1024, placing at end of
Manual order; pre-deletion key not retained) and **FR-162a** (app-launch
unlock via boot-timestamp comparison — remember enabled + no restart →
silent restore + startup sync; otherwise prompt; toggle-off while unlocked
→ immediate Keychain clearance but current session preserved until explicit
lock/exit). Reflected in research.md R30/R31/R32/R33 (R21 refined).

### 4. 第四次 `/speckit-clarify` 会话（FR-031a / FR-180a / FR-090b / FR-141a / FR-022b）

Six additional ambiguities were resolved and encoded in spec.md as **FR-031a**
(single-note JSON export/import reusing the canonical note-envelope schema;
round-trip faithful; file-reference blocks export generic metadata only;
import fails closed on unsupported/corrupted envelopes), **FR-180a** (zh-Hans
+ en UI localization, system-language switch), **FR-090b** (scale limits:
single asset ≤ 50 MB and ≤ 16,384 px longest edge; note structured content
≤ 5 MB; oversize insertions rejected with a localized explanation),
**FR-141a** (auto-save debounce 500 ms; flush before close/delete/quit;
crash-loss window ≤ one debounce window; crash-recovery tests), and
**FR-022b** (Manual-order sort-key divergence reconciled per-note by
last-writer-wins, no conflict copies for sort-key-only divergence — a
documented scoped interpretation of Constitution VIII protecting user
content while treating reorder position as presentation metadata). Whole-
library bulk export/import was explicitly declared a non-goal. Reflected in
research.md R34/R35/R36.

### 5. 第五次 `/speckit-clarify` 会话（FR-040a / FR-041a / FR-050a / FR-110a / FR-014b）

Five ambiguities were resolved and encoded in spec.md as **FR-040a** (one
canonical sRGB hex per built-in color — Yellow #FFE08A, Pink #F9A8C4, Purple
#C9A8E8, Blue #A8CFF9, Green #A8E8B8, Gray #D8D8DC — shared across light/dark,
deterministic input for FR-042 contrast tests), **FR-041a** (opacity adjustable
40%–100% in 5-pt steps, default 100%; contrast validation below 100% against
the composited background), **FR-050a** (emptied blocks stay while the cursor
remains, are removed on cursor exit — merge with adjacent block, final block
stays as empty paragraph — and every removal is single-Undo reversible and
never fires during IME composition), **FR-110a** (change-driven widget refresh:
main app triggers affected widget timeline reloads on data change; no fixed
high-frequency polling, consistent with SC-006), and **FR-014b** (Empty Trash
batch permanent delete with explicit confirmation stating immediate deletion
and loss of the 30-day recoverability guarantee). Reflected in research.md
R37/R38.

### 6. 第六次 `/speckit-clarify` 会话（FR-001a / FR-020a / FR-043a / FR-095a / FR-054）

Five ambiguities were resolved and encoded in spec.md as **FR-001a** (menu-bar
library window positioned with its left edge aligned to the menu-bar icon's
left edge, clamped to the visible screen frame, 4 pt below the menu bar,
instant open/dismiss with no animation), **FR-020a** (card body preview
truncated at 2 rendered lines with a trailing ellipsis; last-modified time
relative within 7 days, then absolute date with the year when in a previous
calendar year), **FR-043a** (per-note text size bounded 9–24 pt in 1-pt steps,
default 13 pt; text ≥18 pt is large text for the FR-042 thresholds),
**FR-095a** (screenshot viewer in an independent borderless note-style window,
zoom 25%–400% in 25% steps, ⌘+/- and double-click actual-size/fit-to-window,
arrow-key navigation between same-note screenshots, Return/double-click enters
caption editing), and **FR-054** (cross-block text selection; copy produces
plain + rich text with supported formatting only; delete removes only selected
characters and merges emptied blocks per FR-050a; trailing padding paragraph
never selectable). Reflected in research.md R40–R43 and in data-model.md +
`contracts/note-document.schema.json` (textSize becomes an integer 9–24 with
default 13, replacing the illustrative small/regular/large/extraLarge enum —
no released schema exists, so no migration is required).

## 二、生成环境注记（原 plan.md "Toolchain note"）

The machine generating this plan had only the Command Line Tools installed
(`xcode-select` → `/Library/Developer/CommandLineTools`); `xcodebuild` was
unavailable, the bundled Swift was 6.4, and the OS was macOS 27.0. This was
**not** the project's intended build environment. Effects: (1) the baseline
Xcode 26.x / Swift 6.3 target is declared as the plan's intent and must be
confirmed in a networked environment with a full Xcode install; (2) high-risk
UI/Widget/capture assumptions cannot be prototyped there and are explicitly
assigned to Milestone 0; (3) external package selection (Argon2id) and exact
macOS-26 API names are recorded in research.md as directions with validation
criteria rather than verified facts. The macOS 26 minimum deployment target is
preserved regardless.

> 注：此注记为 2026-08-06 生成时的环境快照。当前仓库已有 Xcode-beta 环境
> 可编译 GUI 原型（见 tasks.md T158），该 caveat 不再反映现状；部署目标
> 基线仍以 research.md R0 为准。

## 三、原 plan.md 过时注记（已删除/压缩）

- 原 Summary 下 "Note: This is the authoritative technical plan; `tasks.md` is
  intentionally NOT produced by this command"——tasks.md 现已存在（2026-08-07
  起由 `/speckit-tasks` 生成），该注记过时。
- 原 "Constitution Check (re-evaluated after Phase 1 design)" 段中的逐条
  rationale 复述（FR-012a/FR-160e/FR-022a/FR-162a/FR-031a/FR-090b/FR-141a/
  FR-022b/FR-040a/FR-041a/FR-050a/FR-110a/FR-014b/FR-180a/FR-001a/FR-020a/
  FR-043a/FR-095a/FR-054 的决策理由）——已压缩为 plan.md 当前版的结论段，
  各 FR 的完整语义以 spec.md 与 research.md R 条目为准。
