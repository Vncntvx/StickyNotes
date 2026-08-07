# Reading manifest — phase: implement

Generated: 2026-08-07
Active feature: 001-sticky-notes-app
Token budget: ~51000/12000

## Read in full

- `tasks.md` — full task list, ~36000 tokens
  - Why: authoritative execution plan — phases, file paths, module boundaries, task order
- `contracts/provider-protocol.md` — ~800 tokens
  - Why: Provider protocol contract required by SyncCore tasks
- `contracts/provider-errors.md` — ~800 tokens
  - Why: Error contract required by SyncCore tasks
- `contracts/deep-links.md` — ~800 tokens
  - Why: Deep-link contract required by App tasks

## Skim only

- `plan.md` — ~14500 tokens
  - Look for: file paths, module boundaries, Phase definitions, Constitution Check
- `data-model.md` — ~8000 tokens
  - Look for: entity tables (Note, Attachment, Tag, SyncState), GRDB schema decisions

## Skip

- `research.md` — ~12000 tokens — reason: technical decisions already reflected in plan/tasks; consult only if a task cites it
- `quickstart.md` — ~4000 tokens — reason: build/validation commands, needed only at verification time; commands already in AGENTS.md
- `spec.md`, `spec.full.md`, `plan.full.md`, `data-model.full.md`, `tasks.full.md` — backups/uncompacted originals — reason: do not read `.full.md` (token-budget guard); spec content distilled into tasks/plan
- `checklists/*`, `history/*`, `artifact-compaction-report.md` — reason: review gates run separately

## Notes

- **Overflow**: tasks.md alone (~36K tokens) is 3x the 12K soft cap. All
  compacted artifacts are already loaded. Recommended execution strategy:
  **phased run** — load tasks.md Phase 0/1 region only, implement, mark
  `[X]`, then load the next phase region. Do not load tasks.md in one shot.
- Budget assumes ~4 chars/token; actual may differ slightly.
