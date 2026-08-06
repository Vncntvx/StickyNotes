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
| Test frameworks     | Swift Testing (primary), XCTest (where Apple APIs require), XCUITest (critical UI) |

A full Xcode install is **required** to build the app and WidgetExtension
targets, host XCUITest, and run XCTest-based suites. The Command Line Tools
alone cannot build app/Widget targets.

## Detected on this dev machine

> This dev machine generated the spec/plan/tasks artifacts. It is **not** the
> project's intended build environment.

| Component           | Detected                                                              |
|---------------------|-----------------------------------------------------------------------|
| `xcode-select -p`   | `/Library/Developer/CommandLineTools` (Command Line Tools only)       |
| `xcodebuild`        | unavailable (`tool 'xcodebuild' requires Xcode`)                      |
| Swift driver        | 1.168.5 / Apple Swift version 6.4 (swiftlang-6.4.0.27.1)             |
| macOS (dev machine) | 27.0 (build 26A5388g)                                                 |
| SDK in use          | `MacOSX27.0.sdk` (CLT)                                                |
| XCTest framework    | **not present** (CLT ships `Testing.framework` only)                  |
| Swift Testing       | present at `/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework`; the `TestingMacros` plugin lives at `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib` (non-default path); `lib_TestingInterop.dylib` lives at `/Library/Developer/CommandLineTools/Library/Developer/usr/lib/` |

### Effect

1. The StickyCore Swift package **builds** with `swift build` (Swift 6.4, macOS 27 SDK, `macOS(.v26)` deployment target preserved).
2. Swift Testing tests **run** in this environment, but require explicit linker flags to locate the `Testing.framework` and `lib_TestingInterop.dylib`. The helper script `Packages/StickyCore/run-tests-clt.sh` wraps these flags. They are **not** needed in a full Xcode 26.x install.
3. XCTest-based suites (Persistence performance tests, XCUITest, anything importing `XCTest`) **cannot compile** here. They are deferred to a networked full-Xcode environment.
4. The App and WidgetExtension targets **cannot be built** here (no `xcodebuild`, no app-target toolchain). Their resources, entitlements, and source files are written so a full Xcode 26.x install can build them, but the binary `.xcodeproj` is **not** generated on this machine — it must be created with Xcode 26.x (T001).
5. External package resolution (GRDB.swift) requires a GitHub proxy on this machine (`github.com` is unreachable; `api.github.com` and `swiftpackageindex.com` are reachable). The proxy is **not** committed to the repo — it's a local git config (`url.<proxy>.insteadOf`) used during this Phase 1/2 work. A networked environment with direct `github.com` access needs no proxy.

### What this machine CAN do

- Build and unit-test the StickyCore Swift package (Domain, EditorCore, parts of Persistence/AssetStore/SecurityCore/SyncCore that don't require XCTest).
- Verify that GRDB.swift resolves and links against `Persistence`.
- Write all resource/config/contract-test files (entitlements, PrivacyInfo, String Catalogs, CI workflow, contracts).
- Write all Swift source for StickyCore modules and verify they compile.

### What this machine CANNOT do

- Generate or open the binary `StickyNotes.xcodeproj` (T001).
- Build the App or WidgetExtension targets.
- Run XCUITest (T141) or XCTest-based suites.
- Execute Milestone 0 prototypes that require a running app/Widget host (T025a).
- Run the full CI matrix locally (the workflow targets a GitHub Actions macOS runner with Xcode 26.x, not this machine).

## How to run StickyCore tests on a CLT-only machine

```bash
./Packages/StickyCore/run-tests-clt.sh
```

This wraps the Swift Testing invocation with the linker flags needed to
locate `Testing.framework` and `lib_TestingInterop.dylib` in the CLT
install. On a full Xcode 26.x install, plain `swift test` from
`Packages/StickyCore/` suffices.

## How to run the full app build/test

Requires Xcode 26.x (per `quickstart.md`):

```bash
xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test  -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'
```

## Reconciliation with `tasks.md` T001 / `quickstart.md`

- `tasks.md` T001 says: "Create Xcode workspace with macOS app target `App` and Widget Extension target `WidgetExtension`".
- `quickstart.md` uses `StickyNotes.xcodeproj` / scheme `StickyNotes`.

Reconciliation: the project file is named `StickyNotes.xcodeproj` (matches
`quickstart.md`); it contains an app target named `StickyNotes` (scheme
`StickyNotes`) and a Widget Extension target named `WidgetExtension`.
The `App/` directory holds the app target's sources; the `WidgetExtension/`
directory holds the widget target's sources. This naming is consistent with
both documents: T001's `App` refers to the directory/target-role,
`quickstart.md`'s `StickyNotes` refers to the project/scheme/app-target name.

The binary `.xcodeproj` itself must be created with Xcode 26.x — this
machine cannot generate it. The directory layout, entitlements, and
`Package.swift` are written so that opening the project in Xcode 26.x and
adding the two targets (app + widget extension) is the remaining manual
step (T001, deferred to a full-Xcode environment).
