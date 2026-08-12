# 004 Screenshot verification directories

## baseline-screenshots/ (T002)

Baseline captures of the PRE-redesign note window (`main` @ d6e7079) for
visual comparison (plan §9.4 / T054).

Capture procedure (on this Mac, with the app built from the `main` worktree):

```bash
# 1. Build the baseline app from a main-branch worktree and run it.
# 2. Open a note window; set the window to each width below via the
#    standard resize control (or `osascript` System Events size set).
# 3. `screencapture -l <windowID> baseline-<width>.png` (windowID via
#    CGWindowListCopyWindowInfo) — 100% and 60% transparency variants.
```

Widths: 220 / 320 / 480 / 640 / 800 / 1200 / 2000+ pt (each × 100% and 60%).

Status: **CANCELLED (2026-08-13)** — user decision: the screenshot
comparison flow (baseline captures + width-matrix captures + visual
comparison) is cancelled; no captures are required. The procedure below
is kept as historical contract only. Continuous-drag acceptance remains
a manual check (quickstart §3.2, T046).

## width-matrix/ (T046)

Post-redesign captures of the same widths on the current branch, plus a
continuous drag check (quickstart §3.2). Same procedure and width list.

Status: **CANCELLED (2026-08-13)** — user decision: captures are not
required; continuous-drag acceptance (quickstart §3.2) remains the
manual check.

## Verification proxy

The automated suite covers the width contract that screenshots would
assert (spec Required Tests):
- `NoteWindowLifecycleTests` — 220×140 enforced minimum (FR-017a).
- `NoteToolbarStateTests` — fixed item set + visibility-priority mapping
  (FR-015a/015c); the system overflow chevron is a native mechanism.
- `NoteWindowDerivations` tests — "NN%" opacity formatting never
  truncates (FR-009); title derivation (FR-003).
- Full regression — 287 App tests + 196 StickyCore tests green (287 includes
  `windowDeactivationClearsEditorFocusFlag`, 004 FR-012 inactive-window
  format-row regression).
