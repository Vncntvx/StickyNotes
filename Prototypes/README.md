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
| ~~`AppGroupGRDBPrototype`~~ | ~~R6~~ | ~~GRDB `DatabasePool` WAL across two processes in the App Group container; widget-role never migrates~~ | ✅ yes | ✅ REMOVED 2026-08-13 (widget + App Group removal) |
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
swift build                                      # builds all 6 prototypes
swift run MarkdownUndoPrototype                  # headless, exit 0 = PASS
swift run GlobalShortcutPrototype                # headless criteria 1–3
swift run GlobalShortcutPrototype --wait 10      # interactive fire test
swift run Argon2idPrototype                      # headless, exit 0 = PASS
swift run WindowCoordinatorPrototype --selftest  # headless registry test
```

### GUI prototypes — macOS 27 beta: use a `.app` bundle, NOT `swift run`

On macOS 27 beta, launching a GUI prototype via `swift run` (or running the
bare binary directly) shows NO window and the IME/keyboard cannot focus it —
keyboard events stay in the launching terminal (`lsappinfo` reports
`!cgsConnection`). This is a launch-mode limitation of unbundled GUI
processes, NOT a product defect: production launches via LaunchServices
from a real `.app` bundle, where everything works. Verified interactively in
T158 (2026-08-07) — each GUI prototype PASSED when launched as a bundle.

To run a GUI prototype, package it as a minimal `.app` and `open` it:

```bash
# one-time: build + package all GUI prototypes as .app bundles
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
for name in WindowCoordinatorPrototype RichTextIMEPrototype ScreenCapturePrototype; do
  APP="$name.app"
  mkdir -p "$APP/Contents/MacOS"
  cp ".build/out/Products/Debug/$name" "$APP/Contents/MacOS/"
  cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>local.prototype.$name</string>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict>
</plist>
EOF
done

open WindowCoordinatorPrototype.app      # GUI: one-window-per-note + floating
open RichTextIMEPrototype.app            # GUI: type Chinese with IME, Round-trip check
open ScreenCapturePrototype.app          # GUI: system picker + region capture (permission prompt on first capture)
```

Notes on the GUI session: the machine must have an active desktop login
session (launch from a GUI-launched Terminal, not over SSH — SSH-spawned
processes cannot connect to the window server). Each prototype shows its
PASS/FAIL state in the window's status label (stdout is not visible when
launched via `open`).

## Gate report summary (this machine: Xcode-beta 27.0, Swift 6.4, macOS 27 beta)

- Headless criteria all PASS (verified via `DEVELOPER_DIR=… swift run …`).
- GUI prototypes PASS (T158, verified 2026-08-07 on a display-equipped Mac):
  RichTextIMEPrototype (Chinese IME typing + NFC round-trip lossless),
  WindowCoordinatorPrototype (one-window-per-note invariant, focus-to-
  existing, Always-on-Top floating), ScreenCapturePrototype (system
  content-sharing picker; screen-recording permission prompt fires ONLY on
  first capture invocation per FR-131; region drag-capture succeeds). They
  must be launched as `.app` bundles (see "How to run") — `swift run` cannot
  activate windows/IME on macOS 27 beta.
- ~~`AppGroupGRDBPrototype`~~ removed 2026-08-13 with the widget surface and
  the App Group container (R6 is superseded — the SQLite database now lives
  in the app sandbox container).
