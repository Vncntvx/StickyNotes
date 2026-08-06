# Milestone 0 Prototypes (T025a / T155 — hard risk gate)

Scratch prototypes validating the highest-risk assumptions from
`specs/001-sticky-notes-app/research.md` (R0–R18) BEFORE user-story work
depends on them. This package is intentionally separate from
`Packages/StickyCore`; it makes **no** library/test-target changes to the
main package.

## Prototype inventory & gate status

| Prototype | Research | Verifies | Headless? | Status |
|-----------|----------|----------|-----------|--------|
| `MarkdownUndoPrototype` | R1/R5 | Markdown conversion with single-Undo via production `EditorCore` | ✅ yes | ✅ PASS (9 checks) |
| `AppGroupGRDBPrototype` | R6 | GRDB `DatabasePool` WAL across two processes in the App Group container; widget-role never migrates | ✅ yes | ✅ PASS |
| `GlobalShortcutPrototype` | R5 | Carbon `RegisterEventHotKey`: no Accessibility required, conflict detected, unregister/re-register | ✅ criteria 1–3 | ✅ PASS (criteria 1–3); fire test interactive (`--wait`) |
| `Argon2idPrototype` | R9 | SwiftArgon2 v1.0.4: RFC 9106 vector, determinism, wrong-password, 64 MiB KEK bounds | ✅ yes | ✅ PASS (5 checks) |
| `RichTextIMEPrototype` | R1/R16 | SwiftUI `TextEditor` + `AttributedString` with Chinese IME; canonical NFC round-trip | ❌ GUI | ✅ compiles; interactive run required (IME typing + round-trip button) |
| `WindowCoordinatorPrototype` | R3/R4 | One-window-per-note registry + runtime floating level | ⚠️ `--selftest` covers registry; focus/floating interactive | ✅ registry PASS; interactive run required |
| `ScreenCapturePrototype` | R7 | ScreenCaptureKit single frame: system picker (window) + `captureImage(in:)` region overlay; permission on invocation only | ❌ GUI | ✅ compiles; interactive run required (permission prompt) |

## R9 selection record (Argon2id)

**Selected: SwiftArgon2 (`mimiclone/argon2-swift`) v1.0.4** — MIT license,
pure Swift 6, zero transitive dependencies, RFC 9106 compliant (interoperable
with the C reference implementation), `Sendable` + async/await, secure memory
wiping, actively maintained (2026), listed on the Swift Package Index.

All research.md R9 criteria pass:

- Active maintenance ✅ (commits 2026) · permissive license ✅ (MIT)
- Security review history ✅ (RFC 9106 conformance verified by
  `Argon2idPrototype` against the reference vector; pure Swift removes the
  C FFI memory-safety surface)
- Minimal API ✅ (single `Argon2.compute`) · no transitive deps ✅
- Swift 6 / `Sendable` ✅ · Apple platforms ✅ (macOS 15+; deployment target
  macOS 26 is satisfied)
- Replacement strategy ✅ (one-call API surface; documented swap path)
- Known limitations ✅ (pure-Swift Argon2 is slower than the C reference —
  ~1–2 s at m=64 MiB, acceptable and intended for a password-derived KEK)

Candidates considered and rejected: `tmthecoder/Argon2Swift` (inactive since
2023, C FFI wrapper), `calebkleveter/Argon2` (abandoned 2018),
`MarlonJD/argon2id-swift-native` (tiny, 1 star, unproven; SwiftArgon2 has
greater review exposure and test coverage).

Note: the M0 gate item "confirm Xcode 26.x / Swift 6.3 baseline" cannot be
confirmed on this machine (local Xcode-beta 27.0 is newer than the intended
CI baseline); `Documentation/toolchain.md` records the intended baseline and
CI pins Xcode 26.x. The remaining "integrate Argon2id into StickyCore" work
happens in US9 (T111) with the selection above.

## How to run

```bash
swift build                                      # builds all 7 prototypes
swift run MarkdownUndoPrototype                  # headless, exit 0 = PASS
swift run AppGroupGRDBPrototype                  # headless, spawns reader child
swift run GlobalShortcutPrototype                # headless criteria 1–3
swift run GlobalShortcutPrototype --wait 10      # interactive fire test
swift run Argon2idPrototype                      # headless, exit 0 = PASS
swift run WindowCoordinatorPrototype --selftest  # headless registry test
swift run WindowCoordinatorPrototype             # GUI
swift run RichTextIMEPrototype                   # GUI
swift run ScreenCapturePrototype                 # GUI (permission prompt on first capture)
```

## Gate report summary (this machine: Xcode-beta 27.0, Swift 6.4, macOS 27 beta)

- Headless criteria all PASS (verified via `DEVELOPER_DIR=… swift run …`).
- GUI prototypes compile against the macOS 27 SDK; interactive verification
  (real IME typing, window focus/floating, region-drag capture, hotkey
  presses) requires running the executables on a Mac with a display — each
  prints its own PASS/FAIL at the end of the interactive session. This
  interactive verification is tracked as **T158** in `tasks.md`.
- `AppGroupGRDBPrototype` uses a temp directory (the literal App Group
  container path `~/Library/Group Containers/…` is entitlement-gated — an
  unsandboxed CLI cannot create it under macOS TCC; the entitlement path is
  covered by the app target, T005). It leaves a `stickynotes.sqlite` behind
  in its temp dir (OS-cleaned).
- `swift run AppGroupGRDBPrototype` cannot be executed in a TCC-protected
  context twice concurrently — each run uses a unique temp path.
