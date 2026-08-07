# Research Superseded History — macOS Sticky Notes

> **本目录为历史记录**：后续 `speckit.plan` / `speckit-tasks` /
> `speckit-implement` 默认无需阅读本目录；如需追溯某决定的演变过程再查阅。
>
> 以下内容为 research.md 中被 R 条目正文取代的传播记录（2026-08-07 归档）。
> 归档依据：artifact-compaction-report.md §4/§5。所有内容均为**移动**而非
> 复制——research.md 当前版本已不含以下文字。R0–R43 的 Decision / Rationale /
> Alternatives / Risks / Validation 全部保留在当前 research.md 中。

## 2026-08-07 clarification propagation 记录（原 research.md 底部引用块）

以下六个引用块记录了 `/speckit-clarify` 会话成果向 research 的传播过程。
其内容已全部落入 research.md 的 R 条目正文（R15-refined、R19–R43），
此处仅为审计留档。

### 1. 第一/二、三次会话（FR-154/FR-162a/FR-174/FR-191/wrong-vault；FR-022a/FR-023a/FR-072a/FR-090a/FR-094a/FR-140a/FR-152a/FR-160a/b/c/d；FR-012a/FR-160e/FR-022a Trash-restore/FR-162a launch+toggle）

The first pass resolved five encryption/privacy/sync requirements-quality gaps
flagged by `checklists/security.md` (CHK008 repository-replacement, CHK009
diagnostic-bundle boundary, CHK015/CHK042 tombstone retention, CHK043
wrong-vault, CHK064 remember-unlock). These are encoded in spec.md as FR-154
expansion, FR-162a (new), FR-174 expansion, FR-191 expansion, and two new edge
cases. Research entries R15 (refined), R19, R20, R21, R22 (new) capture the
technical decisions.

The second and third passes resolved eleven additional data/security
requirements-quality gaps, promoting previously-illustrative values into
binding spec requirements: FR-022a (sort-key gap=1024/renorm-at-<64), FR-023a
(FTS5 external-content mode), FR-072a (todo maxDepth=6), FR-090a (independent
encrypted asset objects with SHA-256 + partial-failure retry), FR-094a (256px
thumbnail longest edge), FR-140a (5s bounded busy timeout), FR-152a (2-4s sync
debounce), FR-160a (meaningful-metadata positive enumeration), FR-160b
(observable-leakage bound), FR-160c (Argon2id production minimums ≥19 MiB/≥2
iter/≥1 lane), FR-160d (exhaustive fail-closed input list as test vectors).
Research entries R23 (new), R24 (new), R25 (new), R26 (new), R27 (new), and
R9 (refined for FR-160c) capture the technical decisions.

Five additional ambiguities were resolved and encoded in spec.md as FR-012a,
FR-160e, and expansions to FR-022a (Trash-restore) and FR-162a (app-launch
unlock via boot-timestamp comparison; toggle-off while unlocked clears
Keychain immediately but preserves current session until explicit lock/exit).
Research entries R30 (FR-012a), R31 (FR-160e), R32 (FR-022a Trash-restore),
R33 (FR-162a launch + toggle), and R21 (refined for FR-162a) capture the
technical decisions. The `encrypted-envelope.schema.json` contract `$comment`
now references FR-160e.

### 2. UX-gap propagation（FR-014a / SC-004a）

A `checklists/ux.md` coverage review (CHK058) flagged the first-launch
experience as undefined and SC-004 "no visible lag" as unmeasurable. These are
now binding spec requirements **FR-014a** (first-launch: empty-library CTA, no
premature permission prompts, "not configured" sync status, dismissible
onboarding hint never shown again after the first note) and **SC-004a**
(keystroke-to-glyph latency <16 ms). Research entries R28 (first-launch
experience + device-local onboarding-hint state) and R29 (signpost-based
latency measurement) capture the technical decisions. Both are UI/UX-facing;
no impact on contracts or the sync protocol.

### 3. 第四次 `/speckit-clarify` 会话（FR-031a / FR-180a / FR-090b / FR-141a / FR-022b）

FR-031a (single-note JSON export/import reusing the canonical note-envelope
schema, generic-metadata-only file references, fail-closed import), FR-180a
(zh-Hans + en UI localization), FR-090b (scale limits: asset ≤ 50 MB /
≤ 16,384 px; note content ≤ 5 MB; oversize insertions rejected), FR-141a
(auto-save 500 ms debounce + crash-loss window ≤ one debounce window + flush
before close/delete/quit), FR-022b (manual-order sort-key divergence
reconciled per-note by LWW, no conflict copies); whole-library bulk
export/import declared a non-goal. Research entries R34 (FR-031a), R35
(FR-022b), R36 (FR-110a) capture the technical decisions.

### 4. 第五次 `/speckit-clarify` 会话（FR-040a / FR-041a / FR-050a / FR-110a / FR-014b）

FR-040a (canonical sRGB hex per built-in color), FR-041a (opacity 40%–100%,
5-pt steps, default 100%), FR-050a (empty-block removal on cursor exit, final
block preserved, single-Undo, IME-safe), FR-110a (change-driven widget
refresh, no fixed polling), FR-014b (Empty Trash with explicit confirmation).
Research entries R36, R37 (FR-040a/FR-041a), R38 (FR-050a/FR-014b) capture
the technical decisions.

### 5. 第六次 `/speckit-clarify` 会话（FR-001a / FR-020a / FR-043a / FR-095a / FR-054）

FR-001a (menu-bar library window: left-edge-aligned with the icon, clamped to
the screen frame, 4 pt below the menu bar, no open/dismiss animation), FR-020a
(card preview truncated at 2 rendered lines; last-modified time relative
within 7 days, then absolute with the year when in a previous calendar year),
FR-043a (per-note text size 9–24 pt in 1-pt steps, default 13 pt — the
canonical JSON schema and data model now store the integer point size,
replacing the illustrative small/regular/large/extraLarge enum), FR-095a
(screenshot viewer: independent note-style window, zoom 25%–400% in 25% steps,
⌘+/- and double-click actual-size/fit-to-window, arrow-key navigation, Return
caption edit), FR-054 (cross-block selection: spanning selection, plain + rich
copy with supported formatting only, delete removes only selected characters
and merges emptied blocks per FR-050a, trailing padding paragraph never
selectable). Research entries R40, R41, R42, R43 capture the technical
decisions.
