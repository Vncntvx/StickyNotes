# Toolchain

This document records the **detected** Xcode/Swift toolchain for the
StickyNotes project, per `tasks.md` T008 and `research.md` R0.

The macOS 26 minimum deployment target and Swift 6 language mode are
project invariants (constitution II, XI; plan §Technical Context). They
are preserved regardless of the dev machine's own OS version.

## Intended baseline

| Component           | Target                                       |
|---------------------|----------------------------------------------|
| Deployment target   | macOS 26 (preserve even on newer dev OS)     |
| Xcode               | 26.x (preferred 26.6) — full install required |
| Swift language mode | 6 (strict concurrency)                       |
| Swift compiler      | 6.3 (intended)                               |
| SwiftPM             | pinned via `Package.resolved`                |
| Test frameworks     | Swift Testing (primary), XCTest (where Apple APIs require). XCUITest removed 2026-08-13 with the AppUITests target |

A full Xcode install is **required** to build the app target and run
XCTest-based suites.

## Detected on this dev machine (verified 2026-08-07)

> The dev machine runs a **newer** toolchain than the intended CI baseline.
> Code that compiles locally may need to stay within the macOS 26 API
> surface — do not silently raise the deployment target or language mode.

| Component           | Detected                                                              |
|---------------------|-----------------------------------------------------------------------|
| Xcode               | `/Applications/Xcode-beta.app` — Xcode 27.0 (build 27A5228h)          |
| Swift               | 6.4 (swiftlang-6.4.0.27.1)                                            |
| macOS (dev machine) | 27.0 beta                                                             |
| SDK (Xcode-beta)    | `MacOSX27.0.sdk`                                                      |
| `xcode-select -p`   | `/Library/Developer/CommandLineTools` (CLT is the system default)     |
| `Testing.framework` | present under `…/Platforms/MacOSX.platform/Developer/Library/Frameworks/` (Xcode-beta) |
| `XCTest.framework`  | present under Xcode-beta                                              |

### The DEVELOPER_DIR prefix (critical)

`xcode-select -p` points at `/Library/Developer/CommandLineTools`, so a
bare `swift` / `swift test` / `xcodebuild` resolves to the CLT toolchain —
which is **missing `Testing.framework`**, causing every Swift Testing
bundle to fail with `dlopen … Testing.framework … no such file`. This was
previously misdiagnosed as "this machine has only CLT"; in reality a full
Xcode-beta install exists.

**Fix:** prefix every build/test command with
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (no
`sudo xcode-select` needed — keeps the system default on CLT for other
tools). Verified: with that prefix, `swift test` runs all suites green.

```bash
# StickyCore package:
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore

# App target:
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test  -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'
```

### What this machine CAN do (with the DEVELOPER_DIR prefix)

- Build and unit-test the entire StickyCore Swift package (all 7 modules + 7 test targets) — Swift Testing suites run green.
- Build the App target via `xcodebuild` (once `StickyNotes.xcodeproj` exists — T001).
- Run XCTest/Swift Testing-based suites.
- Build and run all Milestone 0 prototypes (`Prototypes/`).
- Verify that GRDB.swift and SwiftArgon2 resolve and link.

### What this machine CANNOT do

- Confirm the Xcode 26.x / Swift 6.3 baseline (local Xcode 27 beta is newer than CI). CI pins Xcode 26.x; the baseline is confirmed when CI first runs green. Code must stay within the macOS 26 API surface.
- Generate the binary `StickyNotes.xcodeproj` if it does not yet exist (T001 — requires creating the project in Xcode-beta).
- Run the full CI matrix locally (the workflow targets a GitHub Actions macOS runner with Xcode 26.x).

## Milestone 0 prototype verification status (T025a / T155 / T158)

The M0 hard gate is **partially** satisfied. `Prototypes/README.md` carries
the full per-prototype report; the status is mirrored here:

- **Headless prototypes** (MarkdownUndo, GlobalShortcut criteria 1–3,
  Argon2id) — **PASS** on this machine (verified via
  `DEVELOPER_DIR=… swift run …`). (AppGroupGRDB prototype removed
  2026-08-13 with the widget surface.)
- **GUI prototypes** (RichTextIME, WindowCoordinator, ScreenCapture) —
  **compile** against the macOS 27 SDK; their interactive criteria (real
  IME typing, window focus/floating, region-drag capture, permission
  prompts) require a Mac with a display. They are documented as
  "interactive run required" in `Prototypes/README.md` and tracked as
  **T158** — the explicit gate for the interactive portion of T025a.
- **Xcode 26.x / Swift 6.3 baseline confirmation** — cannot be confirmed
  here (local Xcode 27 beta is newer). CI pins Xcode 26.x; the baseline
  is confirmed when CI first runs green.

T025a is marked complete for the headless portion; the GUI interactive
verification is T158 (not yet done).

## macOS 27 Liquid Glass API evidence (003 T002, verified 2026-08-09)

Verified against the installed SDK at
`/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.0 27A5228h,
macOS 27.0 SDK). Availability is per the SDK declarations; the project
deployment target stays macOS 26.0.

**Available at macOS 26.0 (usable unguarded)**:

- SwiftUICore/SwiftUI: `glassEffect(_:in:)` (+ `GlassEffectTransition`),
  `Glass` (`.regular/.clear/.identity`, instance methods
  `tint(_:)`/`interactive(_:)`), `GlassEffectContainer`,
  `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`,
  `glassEffectTransition(_:)`, `sharedBackgroundVisibility(_:)`,
  `appearsActive` (10.15+, back-deployed),
  `accessibilityReduceTransparency`, `accessibilityReduceMotion`,
  `accessibilityShowBorders`, `.searchable`.
- AppKit: `NSGlassEffectView` (26.0; incl. `NSGlassEffectContainerView`),
  `NSButton.BezelStyle.glass` (`NSBezelStyleGlass = 16`, 26.0),
  `NSBackgroundExtensionView`, `NSToolbar`, `NSWindowToolbarStyle`.

**Newer than macOS 26.0 — MUST be `#available`-guarded**:

- `ToolbarContent.visibilityPriority(_:)` — macOS 26.1.
- `NSGlassEffectView.effectIsInteractive` — macOS 27.0.

**Confirmed absent (do not use)**:

- `glassEffect(_:in:appliesShadow:cornerRadius:)` overload — not in SDK.
- `ToolbarItemPlacement.search` — no macOS case.

**Baseline record (003 T001, 2026-08-09)**: StickyCore 605 tests in 7
modules green; AppTests 145 tests in 45 suites green; AppUITests runner
cannot initialize in this headless session (UI tests require an
interactive desktop session — environment limitation, not a regression).
Zero code changes at baseline.

**003 T063 (2026-08-09)**: `glassEffect(_:in:)` applied to the custom
block-insertion control under a `#available(macOS 26.0, *)` guard (the
deployment floor — no newer guard needed). `visibilityPriority(_:)`
(26.1) and `NSGlassEffectView.effectIsInteractive` (27.0) are NOT used:
the Library toolbar is AppKit `NSToolbar` (item `visibilityPriority`
property, available since macOS 10.5 — no guard), and the SwiftUI
`glassEffect` handles interactivity. If a future pass adds SwiftUI
`ToolbarContent.visibilityPriority`, it MUST be guarded `#available(macOS
26.1, *)`; `effectIsInteractive` MUST be guarded `#available(macOS 27.0,
*)` — both stay available for CI's Xcode 26.x.

## Reconciliation with `tasks.md` T001 / `quickstart.md`

- `tasks.md` T001 says: "Create Xcode workspace with macOS app target `App`" (the Widget Extension target was removed 2026-08-13).
- `quickstart.md` uses `StickyNotes.xcodeproj` / scheme `StickyNotes`.

Reconciliation: the project file is named `StickyNotes.xcodeproj` (matches
`quickstart.md`); it contains one app target named `StickyNotes` (scheme
`StickyNotes`). The `App/` directory holds the app target's sources. This
naming is consistent with both documents: T001's `App` refers to the
directory/target-role, `quickstart.md`'s `StickyNotes` refers to the
project/scheme/app-target name.
