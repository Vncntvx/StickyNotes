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

Status: **NOT CAPTURED (2026-08-10)** — the agent session could not drive
the interactive GUI (accessory-app bootstrap requires opening the
menu-bar library; AppleScript/CGEvent synthesis was unreliable and the
app-group container stayed empty, so no note window could be opened).
This is a manual task for the human reviewer; the procedure above is the
contract.

## width-matrix/ (T046)

Post-redesign captures of the same widths on the current branch, plus a
continuous drag check (quickstart §3.2). Same procedure and width list.

Status: **NOT CAPTURED (2026-08-10)** — same environment limitation.

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
