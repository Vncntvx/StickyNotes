# Reading manifest — phase: implement

Generated: 2026-08-12T02:40:00+08:00
Active feature: 004-note-window-native-redesign
Token budget: 6256/12000

## Read in full

- `specs/004-note-window-native-redesign/tasks.md` — full, ~4671 tokens
  - Why: implementation is executed task-by-task from this file; all phases, file paths, and TDD red-test ordering live here.
- `specs/004-note-window-native-redesign/data-model.md` — full, ~773 tokens
  - Why: state-ownership rules (single source of truth) constrain every editor/window change.
- `specs/004-note-window-native-redesign/contracts/README.md` — full, ~812 tokens
  - Why: component contracts referenced by tasks (toolbar/selection bridge APIs).

## Skim only

- `specs/004-note-window-native-redesign/plan.md` — ~6339 tokens
  - Look for: §7 文件级变更映射 (line ~278), §2 目标架构/状态所有权 (line ~106), §4 功能交互计划 (line ~206), §8 增量实施阶段 (line ~299). Skim the rest (Constitution Check, risk, non-goals already encoded in tasks).
- `specs/004-note-window-native-redesign/quickstart.md` — ~974 tokens
  - Look for: manual validation steps and any 004-specific build/run commands not already in AGENTS.md.

## Skip

- `specs/004-note-window-native-redesign/spec.md` — ~5574 tokens — reason: FR/SC requirements are fully re-encoded per-task in tasks.md.
- `specs/004-note-window-native-redesign/research.md` — ~2854 tokens — reason: SDK research conclusions already folded into plan §2–§5 and tasks.

## Notes

- No compacted artifacts exist for this feature (no `.full.md` siblings) — sizes above are raw.
- If implement needs spec rationale (SC wording) beyond tasks.md, load spec.md selectively by FR/SC ID rather than whole-file.
